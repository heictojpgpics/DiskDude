//
//  AppUninstaller.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + imports:
//  - Bundles enumerated from /Applications via NSFileManager
//    contentsOfDirectoryAtURL (incl. resource keys)
//  - Info.plist read for bundle id / display name / version
//    (CFBundleShortVersionString / CFBundleIdentifier / CFBundleName)
//  - Last-used dates via Spotlight metadata (MDItemCreate +
//    MDItemCopyAttribute + kMDItemLastUsedDate)
//  - Library leftovers measured per bundle id (recovered strings)
//

import Foundation
import AppKit
import CoreServices

enum AppUninstaller {

    struct InstalledApp: Identifiable, Hashable {
        var id = UUID()
        let bundleURL: URL
        let bundleIdentifier: String
        let displayName: String
        var version: String?
        var lastUsedDate: Date?
        var bundleSize: Int64 = 0
        var leftovers: [LeftoverGroup] = []

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    }

    struct LeftoverGroup: Identifiable, Hashable {
        var id = UUID()
        let category: String
        var urls: [URL]
        var totalSize: Int64 = 0
    }

    /// The Library subfolders searched for leftovers (byte-exact list from
    /// the binary's __cstring literals, kept as "Library/…" home-relative
    /// paths).
    static let leftoverLocations: [(category: String, subpath: String)] = [
        ("Preferences", "Library/Preferences"),
        ("Application Support", "Library/Application Support"),
        ("HTTP Storage", "Library/HTTP Storage"),
        ("Saved Application State", "Library/Saved Application State"),
        ("Containers", "Library/Containers"),
        ("Caches", "Library/Caches"),
        ("Logs", "Library/Logs"),
    ]

    /// Enumerate installed apps from /Applications (and ~/Applications).
    /// Apps are measured together with their Library leftovers
    /// ("Measuring apps and their Library leftovers…").
    static func loadInstalledApps(isCancelled: () -> Bool = { false },
                                   onApp: ((InstalledApp) -> Void)? = nil) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        var roots = [URL(fileURLWithPath: "/Applications")]
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        if fm.fileExists(atPath: userApps.path) { roots.append(userApps) }

        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]) else { continue }
            for item in items where item.pathExtension == "app" {
                if isCancelled() { return apps }
                if let app = measure(bundleURL: item) {
                    apps.append(app)
                    onApp?(app)
                }
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Read bundle metadata and measure the .app size.
    static func measure(bundleURL: URL) -> InstalledApp? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"] ?? bundleURL.deletingPathExtension().lastPathComponent) as? String ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = info["CFBundleShortVersionString"] as? String

        var app = InstalledApp(id: UUID(), bundleURL: bundleURL,
                               bundleIdentifier: bundleID,
                               displayName: name,
                               version: version,
                               lastUsedDate: lastUsedDate(bundleIdentifier: bundleID))
        app.bundleSize = directorySize(bundleURL)
        return app
    }

    /// Spotlight last-used date (MDItemCreate + kMDItemLastUsedDate).
    static func lastUsedDate(bundleIdentifier: String) -> Date? {
        guard let item = MDItemCreate(nil, bundleIdentifier as CFString) else { return nil }
        guard let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return date as? Date
    }

    /// Find leftover files for a bundle id in the Library locations.
    static func findLeftovers(bundleIdentifier: String) -> [LeftoverGroup] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var groups: [LeftoverGroup] = []
        for (category, sub) in leftoverLocations {
            let dir = home.appendingPathComponent(sub)
            var urls: [URL] = []
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]) {
                for item in items {
                    let name = item.lastPathComponent
                    if name.localizedCaseInsensitiveContains(bundleIdentifier) ||
                        matchesBundleName(bundleIdentifier: bundleIdentifier, name: name) {
                        urls.append(item)
                    }
                }
            }
            if !urls.isEmpty {
                var g = LeftoverGroup(id: UUID(), category: category, urls: urls)
                g.totalSize = urls.reduce(0) { $0 + directorySize($1) }
                groups.append(g)
            }
        }
        return groups
    }

    private static func matchesBundleName(bundleIdentifier: String, name: String) -> Bool {
        let parts = bundleIdentifier.split(separator: ".")
        if let last = parts.last, !last.isEmpty {
            return name.localizedCaseInsensitiveContains(String(last))
        }
        return false
    }

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
            return Int64(size)
        }
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey], options: []) else { return 0 }
        var total: Int64 = 0
        for item in items {
            total += directorySize(item)
        }
        return total
    }

    /// Uninstall: quit the app if running, then move the bundle and its
    /// leftovers to the Trash. ("The app is quit first if it's running.")
    /// Returns the list of items that could not be moved.
    static func uninstall(_ app: InstalledApp) -> [URL] {
        // Quit first if running.
        for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier == app.bundleIdentifier {
            running.terminate()
            // Give it a moment to exit.
            Thread.sleep(forTimeInterval: 0.5)
        }
        var failed: [URL] = []
        var urls = [app.bundleURL]
        for group in app.leftovers { urls.append(contentsOf: group.urls) }
        let ok = TrashQueue.recycleSync(urls)
        if !ok { failed = urls }
        return failed
    }
}

/// Small helper that runs NSWorkspace.recycle synchronously.
private enum TrashQueue {
    static func recycleSync(_ urls: [URL]) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var success = false
        NSWorkspace.shared.recycle(urls) { _, error in
            success = (error == nil)
            sem.signal()
        }
        sem.wait()
        return success
    }
}
