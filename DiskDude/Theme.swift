//
//  Theme.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + the decoded Color(red:green:blue:)
//  call sites in the palette-constructor functions: Theme struct with 14
//  colors (background, panel, card, border, divider, chip, track, text,
//  textSecondary, textTertiary, ink, onInk, used, free) + colorScheme,
//  two presets (light/dark) injected into the environment. The RGB values
//  below are byte-exact (Apple system-palette hexes: #FFFFFF, #F5F5F7,
//  #D8D8DD, #E5E5EA, #F2F2F7, #1D1D1F, #6E6E73, #8E8E93, #FF6B4A,
//  #FF3B30, #34C759 / #1E1E20, #28282B, #2C2C2E, #3F3F43, #38383A,
//  #3A3A3C, #FF7A5C, #FF453A, #30D958).
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

    /// Light preset — every value decoded from the shipped binary.
    static let light = Theme(
        background: Color(red: 1, green: 1, blue: 1),
        panel: Color(red: 245/255, green: 245/255, blue: 247/255),
        card: Color(red: 1, green: 1, blue: 1),
        border: Color(red: 216/255, green: 216/255, blue: 221/255),
        divider: Color(red: 229/255, green: 229/255, blue: 234/255),
        chip: Color(red: 242/255, green: 242/255, blue: 247/255),
        track: Color(red: 229/255, green: 229/255, blue: 234/255),
        text: Color(red: 29/255, green: 29/255, blue: 31/255),
        textSecondary: Color(red: 110/255, green: 110/255, blue: 115/255),
        textTertiary: Color(red: 142/255, green: 142/255, blue: 147/255),
        ink: Color(red: 1, green: 107/255, blue: 74/255),
        onInk: .white,
        used: Color(red: 1, green: 59/255, blue: 48/255),
        free: Color(red: 52/255, green: 199/255, blue: 89/255),
        colorScheme: .light
    )

    /// Dark preset — every value decoded from the shipped binary.
    static let dark = Theme(
        background: Color(red: 30/255, green: 30/255, blue: 32/255),
        panel: Color(red: 40/255, green: 40/255, blue: 43/255),
        card: Color(red: 44/255, green: 44/255, blue: 46/255),
        border: Color(red: 63/255, green: 63/255, blue: 67/255),
        divider: Color(red: 56/255, green: 56/255, blue: 58/255),
        chip: Color(red: 58/255, green: 58/255, blue: 60/255),
        track: Color(red: 58/255, green: 58/255, blue: 60/255),
        text: Color(red: 245/255, green: 245/255, blue: 247/255),
        textSecondary: Color(red: 174/255, green: 174/255, blue: 178/255),
        textTertiary: Color(red: 142/255, green: 142/255, blue: 147/255),
        ink: Color(red: 1, green: 122/255, blue: 92/255),
        onInk: .white,
        used: Color(red: 1, green: 69/255, blue: 58/255),
        free: Color(red: 48/255, green: 209/255, blue: 88/255),
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
