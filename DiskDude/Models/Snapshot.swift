//
//  Snapshot.swift
//  DiskDude
//
//  Reconstructed from reflection metadata: Snapshot, Snapshot.Summary,
//  Snapshot.Delta, both CodingKeys enums (Codable, JSON persisted by
//  SnapshotStore).
//

import Foundation

/// A point-in-time capture of folder sizes, persisted as JSON.
struct Snapshot: Codable, Identifiable, Equatable {
    var id: UUID
    var rootPath: String
    var takenAt: Date
    /// folder path -> bytes on disk.
    var folderSizes: [String: Int64]

    enum CodingKeys: String, CodingKey {
        case id
        case rootPath
        case takenAt
        case folderSizes
    }

    init(id: UUID = UUID(), rootPath: String, takenAt: Date = Date(), folderSizes: [String: Int64]) {
        self.id = id
        self.rootPath = rootPath
        self.takenAt = takenAt
        self.folderSizes = folderSizes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        rootPath = try c.decode(String.self, forKey: .rootPath)
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        folderSizes = try c.decode([String: Int64].self, forKey: .folderSizes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(rootPath, forKey: .rootPath)
        try c.encode(takenAt, forKey: .takenAt)
        try c.encode(folderSizes, forKey: .folderSizes)
    }

    /// Compact description used in snapshot lists.
    struct Summary: Codable, Identifiable, Equatable {
        var id: UUID
        var rootPath: String
        var takenAt: Date
        var totalSize: Int64
        var folderCount: Int

        enum CodingKeys: String, CodingKey {
            case id
            case rootPath
            case takenAt
            case totalSize
            case folderCount
        }

        init(id: UUID = UUID(), rootPath: String, takenAt: Date = Date(), totalSize: Int64, folderCount: Int) {
            self.id = id
            self.rootPath = rootPath
            self.takenAt = takenAt
            self.totalSize = totalSize
            self.folderCount = folderCount
        }
    }

    /// One folder's change between two snapshots (used in comparisons).
    struct Delta: Identifiable, Equatable {
        var path: String
        var before: Int64
        var after: Int64

        var id: String { path }
        var grew: Bool { after > before }
        var delta: Int64 { after - before }
    }
}
