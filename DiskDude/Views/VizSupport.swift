//
//  VizSupport.swift
//  DiskDude
//
//  Reconstructed: LayoutCache (class), VizKey, CanvasKey, CachedCanvas,
//  PressableStyle, CardBackground, SectionCaption, SquareIconButton,
//  InkButton, OutlineButton, HoverChip, UsageRing — the shared component
//  kit (exact field sets recovered from reflection metadata).
//

import SwiftUI

// MARK: - Layout cache

/// Key that invalidates a visualization layout when anything relevant
/// changes (scan generation, node, size, depth, color mode).
struct VizKey: Hashable {
    var generation: Int
    var node: ObjectIdentifier
    var width: Int
    var height: Int
    var depth: Int
    var mode: ColorMode
}

/// Full canvas identity: layout + selection + color scheme + labels.
struct CanvasKey: Hashable {
    var layout: VizKey
    var width: Int
    var height: Int
    var selected: ObjectIdentifier?
    var scheme: ColorScheme
    var abbreviateLabels: Bool
}

/// Generic cached layout: layout work happens once per key and is
/// memoized (recovered: class LayoutCache with key/value fields).
final class LayoutCache<Key: Hashable, Value> {
    var key: Key?
    var value: Value?

    func compute(key: Key, _ make: () -> Value) -> Value {
        if let key, key == key, let value { return value }
        let fresh = make()
        self.key = key
        self.value = fresh
        return fresh
    }
}

/// A canvas whose rendering closure is cached by CanvasKey.
struct CachedCanvas: View {
    let key: CanvasKey
    let draw: (GraphicsContext, CGSize) -> Void

    var body: some View {
        Canvas { context, size in
            draw(context, size)
        }
    }
}

// MARK: - Buttons & chrome

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CardBackground: View {
    var radius: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(theme.border, lineWidth: 1))
    }
}

struct SectionCaption: View {
    let title: String
    var trailing: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

struct SquareIconButton: View {
    var systemImage: String?
    var label: String?
    var size: CGFloat = 12
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage, let label {
                    Label(label, systemImage: systemImage)
                } else if let systemImage {
                    Image(systemName: systemImage)
                } else if let label {
                    Text(label)
                }
            }
            .font(.system(size: size, weight: .medium))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.chip))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(label ?? "")
    }
}

struct InkButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 34
    var fontSize: CGFloat = 12
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(height: height)
            .padding(.horizontal, 14)
            .background(Capsule().fill(theme.ink))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Outline button with an optional press-and-confirm state (fields recovered
/// from __swift5_fieldmd: confirmTitle / confirmImage / confirmDuration +
/// the _isConfirming State and its asyncAfter reset timer).
struct OutlineButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 32
    var fontSize: CGFloat = 12
    var confirmTitle: String?
    var confirmImage: String?
    var confirmDuration: Double = 1.2
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var isConfirming = false

    var body: some View {
        Button {
            if confirmTitle != nil {
                if isConfirming {
                    action()
                    isConfirming = false
                } else {
                    withAnimation(.snappy(duration: 0.2)) { isConfirming = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + confirmDuration) {
                        withAnimation(.easeOut(duration: 0.25)) { isConfirming = false }
                    }
                }
            } else {
                action()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isConfirming
                      ? (confirmImage ?? "checkmark.circle.fill")
                      : (systemImage ?? "exclamationmark.triangle.fill"))
                    .font(.system(size: fontSize - 1, weight: .semibold))
                Text(isConfirming ? (confirmTitle ?? title) : title)
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .foregroundStyle(isConfirming ? .white : theme.text)
            .frame(height: height)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(isConfirming ? Color.red : theme.chip)
            )
            .overlay(Capsule().strokeBorder(isConfirming ? Color.clear : theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Data display widgets

struct HoverChip: View {
    let node: FileNode
    var scanSize: Int64 = 0
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(node.isDirectory ? " \(node.name)" : node.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(formatBytes(scanSize > 0 ? scanSize : node.sizeOnDisk))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textSecondary)
            if scanSize > 0 {
                Text(formatPercentage(node.sizeOnDisk, of: scanSize))
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)
            }
            if node.isDirectory {
                Text("\(node.fileCount) files · \(node.folderCount) folders")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(.ultraThinMaterial))
    }
}

struct UsageRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 4
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(theme.ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Byte & percentage formatting

/// Hand-rolled decimal byte formatter used across the app (behavior recovered
/// byte-exact from the binary: 1000-based units, 999.5 rollover, "%.0f"/"%.1f"
/// /"%.2f" selected at 99.95/9.995).
func formatBytes(_ bytes: Int64) -> String {
    let sign = bytes < 0 ? "-" : ""
    let magnitude = abs(bytes)
    if magnitude < 1000 {
        return "\(sign)\(magnitude) B"
    }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(magnitude)
    var unit = 1
    while value >= 999.5 && unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    let pattern = value >= 99.95 ? "%.0f" : (value >= 9.995 ? "%.1f" : "%.2f")
    return sign + String(format: pattern, value) + " " + units[unit]
}

/// Share-of-total percentage (recovered from the binary): "0%" when the total
/// is empty, "<0.1%" for tiny fractions, otherwise one decimal place.
func formatPercentage(_ part: Int64, of whole: Int64) -> String {
    if whole > 0 {
        let fraction = Double(part) / Double(whole) * 100.0
        if fraction <= 0.0 || fraction >= 0.1 {
            return String(format: "%.1f%%", fraction)
        }
        return "<0.1%"
    }
    return "0%"
}
