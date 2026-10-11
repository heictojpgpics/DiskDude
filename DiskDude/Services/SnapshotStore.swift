//
//  SnapshotStore.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + recovered strings:
//  persisted under Application Support/DiskDude/Snapshots with
//  snapshots.json + index.json (JSONEncoder/Decoder imports).
//

import Foundation
import Combine

/// Loads/saves scan snapshots. Snapshots live in
/// ~/Library/Application Support/DiskDude/Snapshots/.
final class SnapshotStore: ObservableObject {

    @Published private(set) var summaries: [Snapshot.Summary] = []
    @Published private(set) var isSaving = false

    /// Directory (Application Support/DiskDude/Snapshots).
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.directory = support.appendingPathComponent("DiskDude/Snapshots", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadSummaries()
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func snapshotURL(_ summary: Snapshot.Summary) -> URL {
        directory.appendingPathComponent("\(summary.id.uuidString).json")
    }

    // MARK: - Loading

    func loadSummaries() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Snapshot.Summary].self, from: data) else {
            // Legacy per-file loads.
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            let loaded: [Snapshot.Summary] = files
                .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
                    return Snapshot.Summary(id: snap.id, rootPath: snap.rootPath,
                                            takenAt: snap.takenAt, totalSize: 0,
                                            folderCount: snap.folderSizes.count)
                }
                .sorted { $0.takenAt > $1.takenAt }
            summaries = loaded
            return
        }
        summaries = list.sorted { $0.takenAt > $1.takenAt }
    }

    /// Load one full snapshot ("Couldn't read one of these snapshots.").
    func load(_ summary: Snapshot.Summary) -> Snapshot? {
        let url = snapshotURL(summary)
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snap
    }

    // MARK: - Saving

    func save(_ snapshot: Snapshot) {
        isSaving = true
        defer { isSaving = false }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else { return }
        let url = snapshotURL(Snapshot.Summary(id: snapshot.id, rootPath: snapshot.rootPath,
                                               takenAt: snapshot.takenAt, totalSize: 0,
                                               folderCount: 0))
        try? data.write(to: url, options: .atomic)

        // Update index.
        let summary = Snapshot.Summary(id: snapshot.id, rootPath: snapshot.rootPath,
                                       takenAt: snapshot.takenAt,
                                       totalSize: snapshot.folderSizes.values.reduce(0, +),
                                       folderCount: snapshot.folderSizes.count)
        var list = summaries.filter { $0.id != summary.id }
        list.append(summary)
        summaries = list.sorted { $0.takenAt > $1.takenAt }
        if let indexData = try? encoder.encode(summaries) {
            try? indexData.write(to: indexURL, options: .atomic)
        }
    }

    func delete(_ summary: Snapshot.Summary) {
        try? FileManager.default.removeItem(at: snapshotURL(summary))
        summaries.removeAll { $0.id == summary.id }
        let encoder = JSONEncoder()
        if let indexData = try? encoder.encode(summaries) {
            try? indexData.write(to: indexURL, options: .atomic)
        }
    }

    /// Build a snapshot from a live scan tree.
    static func snapshot(from root: FileNode) -> Snapshot {
        var folderSizes: [String: Int64] = [:]
        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            guard node.isDirectory else { continue }
            folderSizes[node.path] = node.sizeOnDisk
            stack.append(contentsOf: node.children)
        }
        return Snapshot(rootPath: root.path, folderSizes: folderSizes)
    }

    /// Compare two snapshots ("Pick a Before and an After snapshot to see
    /// what grew."). Returns folder deltas sorted by absolute change.
    static func compare(_ before: Snapshot, _ after: Snapshot) -> [Snapshot.Delta] {
        guard before.rootPath == after.rootPath else { return [] }
        var paths = Set(before.folderSizes.keys)
        paths.formUnion(after.folderSizes.keys)
        return paths
            .map { path in
                Snapshot.Delta(path: path,
                               before: before.folderSizes[path] ?? 0,
                               after: after.folderSizes[path] ?? 0)
            }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
    }
}
