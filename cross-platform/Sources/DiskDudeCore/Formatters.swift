//
//  Formatters.swift
//  DiskDudeCore
//
//  Byte-exact ports of the DiskDude 1.0.1 formatters recovered from the
//  Mach-O (FUN_1000507a8 formatBytes, FUN_100050aac formatPercentage,
//  FUN_100050b70 relativeDateText). Foundation-only: compiles on macOS,
//  Linux and Windows.
//

import Foundation

/// Decimal 1000-based byte formatter (binary-verified):
///  - "<1000" renders integer + " B" (magnitude < 1000 via Int compare)
///  - divide by 1000 FIRST, then test (unit starts at KB)
///  - thresholds 999.5 (rollover), 99.95 (%.0f), 9.995 (%.1f), else %.2f
public func formatBytes(_ bytes: Int64) -> String {
    let sign = bytes < 0 ? "-" : ""
    let magnitude = abs(bytes)
    if magnitude < 1000 {
        return "\(sign)\(magnitude) B"
    }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(magnitude) / 1000
    var unit = 1
    while value >= 999.5 && unit < 5 {
        value /= 1000
        unit += 1
    }
    let pattern = value >= 99.95 ? "%.0f" : (value >= 9.995 ? "%.1f" : "%.2f")
    return sign + String(format: pattern, value) + " " + units[unit]
}

/// Share-of-total percentage (binary-verified): "0%" when the total is
/// empty, "<0.1%" for tiny fractions, otherwise one decimal place.
public func formatPercentage(_ part: Int64, of whole: Int64) -> String {
    if whole > 0 {
        let fraction = Double(part) / Double(whole) * 100.0
        if fraction <= 0.0 || fraction >= 0.1 {
            return String(format: "%.1f%%", fraction)
        }
        return "<0.1%"
    }
    return "0%"
}

/// Relative date text (binary-verified from FUN_100050b70):
/// nil -> "Unknown", < 60 s -> "Just now",
/// else NSRelativeDateTimeFormatter with .full units.
/// The Apple formatter is macOS-only; on other platforms this falls back
/// to the same rules with a compact approximation so tests stay portable.
public func relativeDateText(_ date: Date?, reference: Date = Date()) -> String {
    guard let date = date else { return "Unknown" }
    let interval = date.timeIntervalSince(reference)
    if abs(interval) < 60 { return "Just now" }
    #if canImport(AppKit)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: reference)
    #else
    // Portable fallback (CLI only; the macOS app path above is the
    // byte-exact one used by the GUI build).
    let seconds = abs(interval)
    let minutes = Int(seconds / 60)
    let hours = Int(seconds / 3600)
    let days = Int(seconds / 86400)
    if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
    if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
    if days < 30 { return "\(days) \(days == 1 ? "day" : "days") ago" }
    let months = days / 30
    if months < 12 { return "\(months) \(months == 1 ? "month" : "months") ago" }
    let years = days / 365
    return "\(years) \(years == 1 ? "year" : "years") ago"
    #endif
}
