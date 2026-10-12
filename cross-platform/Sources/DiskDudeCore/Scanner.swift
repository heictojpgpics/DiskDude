//
//  Scanner.swift
//  DiskDudeCore
//
//  Portable scan engine for the CLI (Windows/Linux/macOS). The GUI app
//  uses getattrlistbulk with an NSThread worker pool (macOS-only); this
//  walker reproduces the same accounting on any OS: logical sizes,
//  category totals, top-N items, and hash-based duplicate grouping with
//  the binary's exact thresholds (>= 64 KB to hash, 1 MB chunking).
//

import Foundation

public struct ScanEntry: Sendable {
    public let path: String
    public let size: Int64
    public let category: FileCategory
    public let modified: Date?
}

public struct DuplicateGroup: Sendable {
    public let digest: String
    public let size: Int64
    public let paths: [String]
    public var wasted: Int64 { size * Int64(max(0, paths.count - 1)) }
}

public struct ScanReport: Sendable {
    public let root: String
    public let fileCount: Int
    public let folderCount: Int
    public let totalBytes: Int64
    public let categories: [(category: FileCategory, bytes: Int64)]
    public let topFiles: [ScanEntry]
    public let duplicates: [DuplicateGroup]
    public var duplicateWasted: Int64 { duplicates.reduce(0) { $0 + $1.wasted } }

    /// Deterministic, platform-neutral text rendering (paths use "/" on
    /// every OS) so CI can diff macOS vs Windows vs Linux output exactly.
    public func render(topN: Int = 10) -> String {
        var lines: [String] = []
        lines.append("DiskDude CLI 1.0.1 (recovered core)")
        lines.append("Scan: \(root)")
        lines.append("Files: \(fileCount), Folders: \(folderCount)")
        lines.append("Total: \(formatBytes(totalBytes))")
        lines.append("")
        lines.append("By category:")
        for c in categories where c.bytes > 0 {
            let pct = formatPercentage(c.bytes, of: totalBytes)
            let pad = String(repeating: " ", count: max(1, 11 - c.category.title.count))
            lines.append("  \(c.category.title)\(pad)\(formatBytes(c.bytes))\t\(pct)")
        }
        lines.append("")
        lines.append("Top \(topN) largest files:")
        for (i, f) in topFiles.prefix(topN).enumerated() {
            lines.append("  \(String(format: "%2d", i + 1)). \(f.path)\t\(formatBytes(f.size))")
        }
        lines.append("")
        if duplicates.isEmpty {
            lines.append("Duplicates: none found")
        } else {
            lines.append("Duplicates: \(duplicates.count) group(s), wastes \(formatBytes(duplicateWasted))")
            for g in duplicates {
                lines.append("  group \(g.digest.prefix(12))… (\(g.paths.count) copies, \(formatBytes(g.size)) each)")
                for p in g.paths {
                    lines.append("    \(p)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum Scanner {
    /// Walk `root`, producing the full report. Deterministic ordering
    /// (sorted) so output is identical across platforms.
    public static func scan(root: String,
                            findDuplicates: Bool = true,
                            hashMinimum: Int64 = FileCategory.duplicateMinimumBytes)
        throws -> ScanReport {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        var entries: [ScanEntry] = []
        var folderCount = 0

        var stack: [URL] = [rootURL]
        while let dir = stack.popLast() {
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                    folderCount += 1
                    stack.append(child)
                } else {
                    let size = (try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let modified = try? child.resourceValues(
                        forKeys: [.contentModificationDateKey]).contentModificationDate
                    let ext = child.pathExtension
                    let category: FileCategory = (ext == "app" && isBundle(child))
                        ? .app
                        : FileCategory.category(forExtension: ext)
                    // normalize to forward slashes so sorting + reports are
                    // byte-identical across macOS / Linux / Windows
                    let path = child.path.replacingOccurrences(of: "\\", with: "/")
                    entries.append(ScanEntry(path: path, size: Int64(size),
                                             category: category, modified: modified))
                }
            }
        }

        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        var byCategory: [FileCategory: Int64] = [:]
        for e in entries {
            byCategory[e.category, default: 0] += e.size
        }
        let categories = FileCategory.allCases
            .map { (category: $0, bytes: byCategory[$0] ?? 0) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }

        let top = entries.sorted { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }

        var duplicates: [DuplicateGroup] = []
        if findDuplicates {
            let candidates = entries.filter { $0.size >= hashMinimum }
            var byDigest: [String: [ScanEntry]] = [:]
            for e in candidates.sorted(by: { $0.path < $1.path }) {
                if let digest = try? SHA256.fileDigest(at: e.path) {
                    byDigest[digest, default: []].append(e)
                }
            }
            duplicates = byDigest
                .filter { $0.value.count > 1 }
                .map { digest, group in
                    DuplicateGroup(digest: digest, size: group[0].size,
                                   paths: group.map(\.path).sorted())
                }
                .sorted { $0.paths.first ?? "" < $1.paths.first ?? "" }
        }

        return ScanReport(root: root,
                          fileCount: entries.count,
                          folderCount: folderCount,
                          totalBytes: total,
                          categories: categories,
                          topFiles: Array(top.prefix(50)),
                          duplicates: duplicates)
    }

    private static func isBundle(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }
}
