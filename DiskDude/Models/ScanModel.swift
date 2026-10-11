//
//  ScanModel.swift
//  DiskDude
//
//  Reconstructed from reflection metadata: AppTab, VisualizationMode,
//  ColorMode, DiskInfo, Rankings, AgeReport, ThemeName.
//

import Foundation
import SwiftUI

/// The five top-level tabs of the window.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case explore
    case duplicates
    case applications
    case monitor
    case snapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Explore"
        case .duplicates: return "Duplicates"
        case .applications: return "Apps"
        case .monitor: return "Monitor"
        case .snapshots: return "Snapshots"
        }
    }

    var systemImage: String {
        switch self {
        case .explore: return "square.grid.2x2.fill"
        case .duplicates: return "doc.on.doc"
        case .applications: return "shippingbox.fill"
        case .monitor: return "waveform.path.ecg"
        case .snapshots: return "clock.arrow.circlepath"
        }
    }
}

/// The nine visualization modes on the Explore tab.
enum VisualizationMode: String, CaseIterable, Identifiable, Hashable {
    case treemap
    case folders
    case sunburst
    case flame
    case bubbles
    case mindMap
    case topSizes
    case ageMap
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treemap: return "Treemap"
        case .folders: return "Folders"
        case .sunburst: return "Sunburst"
        case .flame: return "Flame"
        case .bubbles: return "Bubbles"
        case .mindMap: return "Mind Map"
        case .topSizes: return "Top Sizes"
        case .ageMap: return "Age Map"
        case .outline: return "Outline"
        }
    }

    // SF Symbol names recovered from __cstring xrefs (0x100092678 etc.):
    // square.grid.2x2.fill, square.on.square, circle.hexagongrid.fill,
    // square.3.layers.3d, smallcircle.filled.circle,
    // point.3.filled.connected.trianglepath.dotted, doc.plaintext.fill,
    // clock.arrow.circlepath, list.bullet.rectangle.
    var systemImage: String {
        switch self {
        case .treemap: return "square.grid.2x2.fill"
        case .folders: return "square.on.square"
        case .sunburst: return "circle.hexagongrid.fill"
        case .flame: return "square.3.layers.3d"
        case .bubbles: return "smallcircle.filled.circle"
        case .mindMap: return "point.3.filled.connected.trianglepath.dotted"
        case .topSizes: return "doc.plaintext.fill"
        case .ageMap: return "clock.arrow.circlepath"
        case .outline: return "list.bullet.rectangle"
        }
    }

    /// Caption shown in the mode picker, recovered from __cstring xrefs.
    var caption: String {
        switch self {
        case .treemap: return "Every file as a rectangle, sized by bytes"
        case .folders: return "Browse folder by folder, sized as you go"
        case .sunburst: return "Rings radiating out from the scan root"
        case .flame: return "Depth top to bottom, size left to right"
        case .bubbles: return "Nested bubbles, one per folder"
        case .mindMap: return "Branches from the root, sized by weight"
        case .topSizes: return "The biggest items, ranked"
        case .ageMap: return "Where your bytes sit on a timeline"
        case .outline: return "Every item as an expandable outline"
        }
    }
}

/// How folders/files are colored.
enum ColorMode: String, CaseIterable, Identifiable, Hashable {
    case type
    case folder
    case age

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Type"
        case .folder: return "Folder"
        case .age: return "Age"
        }
    }
}

/// Two theme presets used by the Theme struct.
enum ThemeName: String, CaseIterable, Identifiable, Hashable {
    case light
    case dark

    var id: String { rawValue }
}

/// Volume-level summary shown in the top bar.
struct DiskInfo: Equatable {
    var name: String
    var total: Int64
    var free: Int64

    var used: Int64 { total - free }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// Ranking buckets for the Top Sizes tab: biggest files & folders anywhere.
struct Rankings: Equatable {
    var files: [FileNode]
    var folders: [FileNode]
}

/// Age distribution for the Age Map / Untouched cards.
struct AgeReport: Equatable {
    /// Byte totals per age bucket (index == AgeBucket order).
    var buckets: [Int64]
    var total: Int64
    /// Byte totals keyed by month number.
    var months: [Int: [Int64]]
    /// Files over the "untouched" threshold (a year, 40 MB).
    var untouched: [FileNode]
    var untouchedTotal: Int64
}

enum Discard: Error {
    case value
}
