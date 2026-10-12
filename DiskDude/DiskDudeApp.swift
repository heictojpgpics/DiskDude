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

    init() {
        // Binary-verified developer hooks (FUN_10000ebf0):
        //   ProcessInfo.processInfo.environment["DISKDUDE_MODE"] -> _findStringSwitchCase
        //   ("light"/"dark") -> writes themeName @Published via keypaths
        //   environment["DISKDUDE_SCAN"] -> auto-scan starts on app activation:
        //   the binary registers an NSApplicationDidBecomeActiveNotification
        //   observer (main queue) that launches a DispatchWorkItem (.userInitiated)
        //   to start the scan. Standard "theme" UserDefaults key is read inside
        //   ScanViewModel.
        let env = ProcessInfo.processInfo.environment
        if let mode = env["DISKDUDE_MODE"] {
            switch mode {
            case "light": viewModel.themeName = .light
            case "dark": viewModel.themeName = .dark
            default: break
            }
        }
        if let scanPath = env["DISKDUDE_SCAN"] {
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak viewModel] _ in
                let work = DispatchWorkItem(qos: .userInitiated) { [weak viewModel] in
                    viewModel?.startAutoScan(path: scanPath)
                }
                DispatchQueue.main.async(execute: work)
            }
        }
    }

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
