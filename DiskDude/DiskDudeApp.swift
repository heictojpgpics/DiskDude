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
