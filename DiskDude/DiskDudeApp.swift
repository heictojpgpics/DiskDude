//
//  DiskDudeApp.swift
//  DiskDude
//
//  Reconstructed: @main SwiftUI App with WindowGroup (Scene metadata
//  confirmed via getOpaqueTypeConformance2 + App protocol conformance).
//  Appearance management via NSApplication setAppearance/effectiveAppearance
//  (imports recovered: bestMatchFromAppearancesWithNames_).
//

import SwiftUI
import AppKit

@main
struct DiskDudeApp: App {
    // Binary-verified architecture (FUN_10000ebf0 + keypath writes): the
    // DISKDUDE_MODE / DISKDUDE_SCAN env hooks live inside ScanViewModel's
    // own initialization region (Published writes via
    // Published._enclosingInstance on the class instance itself — NOT via
    // the App struct's @StateObject wrapper, which would materialize a
    // temporary instance disconnected from the installed view tree; that
    // mismatch is exactly why an env-driven auto-scan never fired in the
    // rebuilt app while the original scans).
    @StateObject private var viewModel = ScanViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environment(\.theme, Theme.theme(for: viewModel.themeName))
                .preferredColorScheme(viewModel.themeName == .dark ? .dark : .light)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Folder…") {
                    NotificationCenter.default.post(name: .chooseScanFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let chooseScanFolder = Notification.Name("DiskDudeChooseScanFolder")
}

/// Applies the named appearance app-wide (light/dark), matching the
/// recovered NSAppearance usage.
enum Appearance {
    static func apply(_ name: ThemeName) {
        if let app = NSApplication.shared as NSApplication? {
            let appearance = NSAppearance(named: name == .dark ? .darkAqua : .aqua)
            app.appearance = appearance
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
        }
    }
}
