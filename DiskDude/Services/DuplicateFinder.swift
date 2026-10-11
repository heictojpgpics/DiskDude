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

    /// Files smaller than this are skipped (recovered from the binary:
    /// the candidate filter compares against 0x10000 = 64 KB).
    static let minimumSize: Int64 = 0x10000  // 64 KB

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

    /// Stream hash the file — byte-exact recovery of the shipped algorithm:
    /// open(2) with O_CLOEXEC, fcntl(F_NOCACHE, 1) on full reads so hashing
    /// does not evict the page cache, 1 MB chunks fed to the incremental
    /// CryptoKit hasher via UnsafeRawBufferPointer, whole file for sizes
    /// under 1 MB.
    static func sha256(path: String, size: Int, fullRead: Bool) -> SHA256Digest? {
        let fd = open(path, O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var remaining = size
        if fullRead {
            fcntl(fd, F_NOCACHE, 1)
            remaining = Int.max
        }
        let chunkSize = remaining > 0xFFFFF ? 1 << 20 : max(remaining, 1)
        let buffer = malloc(chunkSize)!
        defer { free(buffer) }
        var hasher = SHA256()
        while remaining > 0 {
            let toRead = min(chunkSize, remaining)
            let n = read(fd, buffer, toRead)
            if n <= 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n))
            remaining -= n
        }
        return hasher.finalize()
    }

    static func sha256(url: URL) -> SHA256Digest? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return sha256(path: url.path, size: size, fullRead: true)
    }
}
