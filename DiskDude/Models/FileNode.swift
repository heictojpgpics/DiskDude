//
//  FileNode.swift
//  DiskDude
//
//  Reconstructed from DiskDude 1.0.1 (arm64) reflection metadata.
//  Field names, types, and var/let modifiers recovered from
//  __swift5_fieldmd / __swift5_typeref / ObjC ivar layout.
//

import Foundation

/// Category used for coloring and stats buckets in the visualizations.
enum FileCategory: Int, CaseIterable, Codable {
    case video
    case audio
    case image
    case document
    case developer
    case archive
    case application
    case system
    case other

    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        case .document: return "Document"
        case .developer: return "Developer"
        case .archive: return "Archive"
        case .application: return "App"
        case .system: return "System"
        case .other: return "Other"
        }
    }
}

/// A node in the scanned folder tree. One instance exists per file or folder;
/// sizes and counts roll up from children.
final class FileNode: Identifiable, Hashable, ObservableObject {

    let name: String
    let isDirectory: Bool

    var category: FileCategory = .other
    var children: [FileNode] = []
    weak var parent: FileNode?
    var rootPath: String?

    var logicalSize: Int64 = 0
    var sizeOnDisk: Int64 = 0
    var modifiedStamp: Double = 0
    var createdStamp: Double = 0
    var typeSizes: [Int64]?
    var fileCount: Int = 0
    var folderCount: Int = 0

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, isDirectory: Bool, rootPath: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.rootPath = rootPath
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    /// Total size used for drawing and ranking (bytes on disk).
    var displaySize: Int64 { sizeOnDisk }

    /// Depth from the scan root (root == 0).
    var depth: Int {
        var d = 0
        var node = parent
        while let p = node {
            d += 1
            node = p.parent
        }
        return d
    }

    /// Breadcrumb path of names from the root down to this node.
    var path: String {
        var parts: [String] = []
        var node: FileNode? = self
        while let n = node {
            parts.append(n.name)
            node = n.parent
        }
        return parts.reversed().joined(separator: "/")
    }

    /// Sorted-by-size children (largest first), used by every visualization.
    var sortedChildren: [FileNode] {
        children.sorted { $0.sizeOnDisk > $1.sizeOnDisk }
    }

    /// Share of the parent's size (0...1), used for fan widths and cells.
    var shareOfParent: Double {
        guard let p = parent, p.sizeOnDisk > 0 else { return 1 }
        return Double(sizeOnDisk) / Double(p.sizeOnDisk)
    }

    /// Adds a child and rolls up sizes/counts through the ancestor chain.
    func add(child: FileNode) {
        child.parent = self
        children.append(child)
        absorb(child)
    }

    /// Rolls a child's totals into this node and its ancestors.
    private func absorb(_ child: FileNode) {
        logicalSize += child.logicalSize
        sizeOnDisk += child.sizeOnDisk
        fileCount += child.fileCount
        folderCount += child.folderCount
        if child.isDirectory { folderCount += 1 } else { fileCount += 1 }
        accumulateTypeSizes(from: child)
        if child.modifiedStamp > modifiedStamp { modifiedStamp = child.modifiedStamp }
        if child.createdStamp != 0 && (createdStamp == 0 || child.createdStamp < createdStamp) {
            createdStamp = child.createdStamp
        }
        parent?.absorb(self)
    }

    /// Keeps a per-category byte total (index == FileCategory.rawValue).
    private func accumulateTypeSizes(from child: FileNode) {
        guard !isDirectory || children.isEmpty == false else { return }
        var sizes = typeSizes ?? Array(repeating: 0, count: FileCategory.allCases.count)
        if child.isDirectory, let childSizes = child.typeSizes {
            for (i, v) in childSizes.enumerated() where i < sizes.count {
                sizes[i] += v
            }
        } else if child.isDirectory == false {
            let idx = child.category.rawValue
            if idx < sizes.count { sizes[idx] += child.sizeOnDisk }
        }
        typeSizes = sizes
    }

    /// Size of one category inside this folder, or this node's own size for files.
    func size(for category: FileCategory) -> Int64 {
        if !isDirectory { return self.category == category ? sizeOnDisk : 0 }
        return typeSizes?[safe: category.rawValue] ?? 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Identity box used as a dictionary key / erasure for FileNode.
struct NodeBox: Hashable, Identifiable {
    let node: FileNode
    var id: ObjectIdentifier { node.id }

    static func == (lhs: NodeBox, rhs: NodeBox) -> Bool {
        lhs.node === rhs.node
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(node.id)
    }
}
