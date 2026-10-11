//
//  DuplicateFinder.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + imports:
//  SHA256 (CryptoKit) digests with size pre-grouping. Only files above a
//  threshold are hashed. Groups report a wasted-bytes total.
//

import Foundation
import CryptoKit

enum DuplicateFinder {

    /// Grouping key: files with equal size AND SHA-256 digest fall into
    /// the same group (recovered struct Key: size, digest).
    struct Key: Hashable {
        var size: Int64
        var digest: SHA256Digest
    }

    /// One group of byte-identical files.
    struct Group: Identifiable, Hashable {
        var id: UUID = UUID()
        var size: Int64
        var files: [FileNode]

        /// Bytes wasted by the extra copies ("wastes N" chip).
        var wasted: Int64 { max(0, size * Int64(files.count - 1)) }
    }

    /// Files smaller than this are skipped (small files are rarely worth
    /// reporting; the exact threshold was tuned in the original build).
    static let minimumSize: Int64 = 1_048_576  // 1 MB

    /// Find duplicate files under `root`, reporting groups as they are
    /// found via `onGroup`.
    static func findDuplicates(in root: FileNode,
                               isCancelled: () -> Bool = { false },
                               onGroup: ((Group) -> Void)? = nil) -> [Group] {
        // 1. Collect candidate files.
        var candidates: [FileNode] = []
        collect(from: root, into: &candidates, isCancelled: isCancelled)

        // 2. Group by size first (files with different sizes can't match).
        var bySize: [Int64: [FileNode]] = [:]
        for file in candidates where file.sizeOnDisk >= minimumSize {
            bySize[file.sizeOnDisk, default: []].append(file)
        }

        var groups: [Group] = []
        for (_, files) in bySize where files.count > 1 {
            if isCancelled() { break }
            // 3. Within each size bucket, group by SHA256 digest.
            var byDigest: [Key: [FileNode]] = [:]
            for file in files {
                if isCancelled() { break }
                guard let digest = sha256(url: URL(fileURLWithPath: file.path)) else { continue }
                byDigest[Key(size: file.sizeOnDisk, digest: digest), default: []].append(file)
            }
            for bucket in byDigest.values where bucket.count > 1 {
                let group = Group(size: bucket[0].sizeOnDisk, files: bucket.sorted { $0.path < $1.path })
                groups.append(group)
                onGroup?(group)
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func collect(from node: FileNode, into out: inout [FileNode],
                                isCancelled: () -> Bool) {
        if isCancelled() { return }
        if node.isDirectory {
            for child in node.children {
                collect(from: child, into: &out, isCancelled: isCancelled)
            }
        } else {
            out.append(node)
        }
    }

    /// Stream hash the file (chunked reads — recovered: fopen/fread/fclose
    /// imports alongside the SHA256 digest usage).
    static func sha256(url: URL) -> SHA256Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}
