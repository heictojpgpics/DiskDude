//
//  Theme.swift
//  DiskDude
//
//  Reconstructed from reflection metadata: Theme struct with 11 colors
//  (background, panel, card, border, divider, chip, track, text,
//  textSecondary, textTertiary, ink), two presets (light/dark),
//  injected into the environment as an EnvironmentObject/Environment value.
//

import SwiftUI

struct Theme: Equatable {
    var background: Color
    var panel: Color
    var card: Color
    var border: Color
    var divider: Color
    var chip: Color
    var track: Color
    var text: Color
    var textSecondary: Color
    var textTertiary: Color
    var ink: Color
    var onInk: Color
    var used: Color
    var free: Color
    var colorScheme: ColorScheme

    /// Category palette used by the visualizations (ColorMode.type).
    func categoryColor(_ category: FileCategory) -> Color {
        switch category {
        case .video: return Color(red: 0.85, green: 0.33, blue: 0.29)
        case .audio: return Color(red: 0.94, green: 0.56, blue: 0.20)
        case .image: return Color(red: 0.95, green: 0.77, blue: 0.26)
        case .document: return Color(red: 0.28, green: 0.67, blue: 0.29)
        case .developer: return Color(red: 0.26, green: 0.60, blue: 0.96)
        case .archive: return Color(red: 0.61, green: 0.35, blue: 0.71)
        case .application: return Color(red: 0.25, green: 0.75, blue: 0.75)
        case .system: return Color(red: 0.49, green: 0.49, blue: 0.52)
        case .other: return Color(red: 0.62, green: 0.62, blue: 0.65)
        }
    }

    /// Age heat ramp used by the Age Map (old = warm, new = cool).
    func ageColor(age: TimeInterval, maxAge: TimeInterval) -> Color {
        guard maxAge > 0 else { return .gray }
        let t = min(1, max(0, age / maxAge))
        return Color(hue: 0.08 * t, saturation: 0.75, brightness: 0.92 - 0.25 * t)
    }

    /// Folder depth ramp used by folder-mode coloring.
    func folderColor(depth: Int) -> Color {
        let hue = Double(depth % 6) / 6.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.85)
    }

    static let light = Theme(
        background: Color(NSColor.controlBackgroundColor),
        panel: Color(NSColor.windowBackgroundColor),
        card: Color.white.opacity(0.92),
        border: Color.black.opacity(0.12),
        divider: Color.black.opacity(0.10),
        chip: Color.black.opacity(0.06),
        track: Color.black.opacity(0.10),
        text: Color.primary,
        textSecondary: Color.primary.opacity(0.65),
        textTertiary: Color.primary.opacity(0.4),
        ink: Color(red: 0.16, green: 0.28, blue: 0.92),
        onInk: .white,
        used: Color(red: 0.16, green: 0.28, blue: 0.92),
        free: Color.green.opacity(0.75),
        colorScheme: .light
    )

    static let dark = Theme(
        background: Color(red: 0.10, green: 0.10, blue: 0.12),
        panel: Color(red: 0.13, green: 0.13, blue: 0.16),
        card: Color.white.opacity(0.06),
        border: Color.white.opacity(0.14),
        divider: Color.white.opacity(0.10),
        chip: Color.white.opacity(0.09),
        track: Color.white.opacity(0.14),
        text: Color.white,
        textSecondary: Color.white.opacity(0.70),
        textTertiary: Color.white.opacity(0.45),
        ink: Color(red: 0.55, green: 0.65, blue: 1.0),
        onInk: .white,
        used: Color(red: 0.55, green: 0.65, blue: 1.0),
        free: Color.green.opacity(0.8),
        colorScheme: .dark
    )

    static func theme(for name: ThemeName) -> Theme {
        name == .dark ? .dark : .light
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
