//
//  QuickWins.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + recovered strings:
//  seven categories (downloads, caches, simulators, largeMedia,
//  nodeModules, buildArtifacts, derivedData) matched against known
//  paths like ~/Downloads, ~/Library/Caches/CoreSimulator, and
//  "Xcode DerivedData".
//

import Foundation

enum QuickWins {

    struct Category: Identifiable, Hashable {
        var kind: Kind
        var matches: [FileNode]
        var itemCount: Int

        var id: String { kind.rawValue }

        var totalSize: Int64 { matches.reduce(0) { $0 + $1.sizeOnDisk } }
    }

    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case downloads
        case caches
        case simulators
        case largeMedia
        case nodeModules
        case buildArtifacts
        case derivedData

        var id: String { rawValue }

        var title: String {
            switch self {
            case .downloads: return "Downloads"
            case .caches: return "Caches & logs"
            case .simulators: return "iOS Simulators"
            case .largeMedia: return "Large media"
            case .nodeModules: return "node_modules"
            case .buildArtifacts: return "Build artifacts"
            case .derivedData: return "Xcode DerivedData"
            }
        }
    }

    /// Find recoverable space under the scan root, bucketed by category.
    /// Threshold sizes mirror the original heuristics (40 MB media floor
    /// from the recovered "Nothing over 40 MB…" string).
    static func find(in root: FileNode) -> [Category] {
        var out: [Category] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        for kind in Kind.allCases {
            let matches = matchesFor(kind: kind, root: root, home: home)
            if !matches.isEmpty {
                out.append(Category(kind: kind, matches: matches, itemCount: matches.count))
            }
        }
        return out
    }

    private static func matchesFor(kind: Kind, root: FileNode, home: String) -> [FileNode] {
        switch kind {
        case .downloads:
            // Everything in ~/Downloads over a floor size.
            return root.descendants(in: "Downloads")
        case .caches:
            return root.descendants(namedAny: ["Caches", "logs"], minSize: 256 * 1024 * 1024)
        case .simulators:
            return root.descendants(namedAny: ["CoreSimulator", "Devices"], minSize: 1024 * 1024 * 1024)
        case .largeMedia:
            // Single media files over 40 MB.
            return root.descendants { node in
                guard !node.isDirectory else { return false }
                let isMedia = node.category == .video || node.category == .audio || node.category == .image
                return isMedia && node.sizeOnDisk > 40 * 1024 * 1024
            }
        case .nodeModules:
            return root.descendants(named: "node_modules")
        case .buildArtifacts:
            return root.descendants(namedAny: ["build", "Build", "DerivedData", "buildArtifacts"], minSize: 64 * 1024 * 1024)
        case .derivedData:
            return root.descendants(named: "DerivedData")
        }
    }
}

extension FileNode {
    /// Depth-first search collecting nodes matching the predicate.
    func descendants(where predicate: (FileNode) -> Bool) -> [FileNode] {
        var out: [FileNode] = []
        var stack: [FileNode] = children
        while let node = stack.popLast() {
            if predicate(node) {
                out.append(node)
            } else {
                stack.append(contentsOf: node.children)
            }
        }
        return out
    }

    func descendants(named name: String, minSize: Int64 = 0) -> [FileNode] {
        descendants { $0.isDirectory && $0.name == name && $0.sizeOnDisk >= minSize }
    }

    func descendants(namedAny names: [String], minSize: Int64 = 0) -> [FileNode] {
        descendants { $0.isDirectory && names.contains($0.name) && $0.sizeOnDisk >= minSize }
    }

    func descendants(in folderName: String) -> [FileNode] {
        descendants { $0.name == folderName || $0.parent?.name == folderName }
    }
}
