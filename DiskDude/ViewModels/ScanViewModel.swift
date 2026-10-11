//
//  ScanViewModel.swift
//  DiskDude
//
//  Reconstructed from reflection metadata: ObservableObject with 26
//  @Published properties (exact names/types from __swift5_fieldmd) plus
//  the non-published service references. Behavior reconstructed from
//  decompiled call sequences, string usage, and UserDefaults keys
//  (DISKDUDE_MODE, DISKDUDE_SCAN, recentScans).
//

import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class ScanViewModel: ObservableObject {

    enum Status: Equatable {
        case idle
        case scanning(Int)
        case done
    }

    // MARK: - Published state (order recovered from field metadata)

    @Published var status: Status = .idle
    @Published var root: FileNode?
    @Published var currentFolder: FileNode?
    @Published var selectedNode: FileNode?
    @Published var quickWins: [QuickWins.Category] = []
    @Published var duplicateGroups: [DuplicateFinder.Group] = []
    @Published var isFindingDuplicates = false
    @Published var installedApps: [AppUninstaller.InstalledApp] = []
    @Published var isLoadingApps = false
    @Published var tab: AppTab = .explore
    @Published var mode: VisualizationMode = .treemap
    @Published var colorMode: ColorMode = .type
    @Published var depth: Double = 3
    @Published var abbreviateLabels = false
    @Published var filter: String = ""
    @Published var showInspector = false
    @Published var themeName: ThemeName = .light
    @Published var disk = DiskInfo(name: "Macintosh HD", total: 0, free: 0)
    @Published var scanDuration: Double = 0
    @Published var recents: [URL] = []
    @Published var generation = 0
    /// Per-folder age reports, built asynchronously after a scan
    /// ("Reading modification dates…", pendingReports tracks in-flight folders).
    @Published var ageReports: [String: AgeReport] = [:]
    @Published var rankings = Rankings(files: [], folders: [])
    @Published var unreadableFolderCount = 0
    @Published var unreadableFolderSamples: [String] = []
    @Published var showAccessNotice = false

    // MARK: - Services

    let cleanupQueue = CleanupQueue()
    let snapshotStore = SnapshotStore()
    var scanTask: Task<Void, Never>?
    var scanner: DiskScanner?
    var pendingReports: Set<String> = []
    var activationObserver: NSObject?

    // MARK: - Init

    init() {
        restoreSettings()
        observeActivation()
        refreshDiskInfo()
    }

    deinit {
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func restoreSettings() {
        let defaults = UserDefaults.standard
        // DISKDUDE_MODE stores the visualization mode across launches.
        if let modeRaw = defaults.string(forKey: "DISKDUDE_MODE"),
           let saved = VisualizationMode(rawValue: modeRaw) {
            mode = saved
        }
        // DISKDUDE_SCAN / recentScans store recent scan folders.
        if let data = defaults.data(forKey: "DISKDUDE_SCAN") {
            recents = (try? JSONDecoder().decode([URL].self, from: data)) ?? []
        } else if let paths = defaults.stringArray(forKey: "recentScans") {
            recents = paths.map { URL(fileURLWithPath: $0) }
        }
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: "DISKDUDE_MODE")
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: "DISKDUDE_SCAN")
        }
    }

    /// Track app activation to re-check volume info
    /// (NSApplicationDidBecomeActiveNotification import confirmed).
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDiskInfo() }
        }
    }

    // MARK: - Disk info

    func refreshDiskInfo() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey,
            .volumeIsInternalKey, .volumeLocalizedNameKey,
        ]
        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) {
            for volume in volumes {
                guard let values = try? volume.resourceValues(forKeys: keys),
                      let name = values.volumeLocalizedName ?? values.volumeName,
                      values.volumeIsBrowsable == true,
                      values.volumeIsInternal == true else { continue }
                let total = Int64(values.volumeTotalCapacity ?? 0)
                let free = values.volumeAvailableCapacityForImportantUsage.map(Int64.init)
                    ?? Int64(values.volumeAvailableCapacity ?? 0)
                disk = DiskInfo(name: name, total: total, free: free)
                break
            }
        }
    }

    // MARK: - Scanning

    func scan(root url: URL) {
        guard case .idle = status else { return }
        status = .scanning(0)
        scanDuration = 0
        generation += 1
        addRecent(url)

        let scanner = DiskScanner()
        self.scanner = scanner
        let start = Date()

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let root = scanner.scan(rootURL: url) { files, bytes, current in
                Task { @MainActor in
                    self?.status = .scanning(files)
                }
            }
            let elapsed = Date().timeIntervalSince(start)
            let unreadableCount = scanner.unreadableCount
            let unreadableSamples = scanner.unreadableSamples

            await MainActor.run {
                guard let self else { return }
                self.root = root
                self.currentFolder = root
                self.selectedNode = nil
                self.scanDuration = elapsed
                self.unreadableFolderCount = unreadableCount
                self.unreadableFolderSamples = unreadableSamples
                self.showAccessNotice = unreadableCount > 0
                self.status = .done
                self.rankings = self.buildRankings(from: root)
                self.quickWins = QuickWins.find(in: root)
                self.beginAgeReports(for: root)
                self.persistSettings()
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanTask?.cancel()
        status = .idle
    }

    private func addRecent(_ url: URL) {
        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        if recents.count > 6 { recents = Array(recents.prefix(6)) }
    }

    // MARK: - Derived data

    private func buildRankings(from root: FileNode) -> Rankings {
        var files: [FileNode] = []
        var folders: [FileNode] = []
        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            if node.isDirectory && node !== root {
                folders.append(node)
                stack.append(contentsOf: node.children)
            } else if !node.isDirectory {
                files.append(node)
            }
        }
        return Rankings(files: Array(files.sorted { $0.sizeOnDisk > $1.sizeOnDisk }.prefix(100)),
                        folders: Array(folders.sorted { $0.sizeOnDisk > $1.sizeOnDisk }.prefix(100)))
    }

    /// Age reports are computed folder-by-folder off the main actor;
    /// pendingReports tracks which folders are still in flight.
    private func beginAgeReports(for root: FileNode) {
        ageReports = [:]
        pendingReports = []
        let folders = topFolders(from: root, limit: 8)
        for folder in folders {
            let path = folder.path
            pendingReports.insert(path)
            Task.detached(priority: .utility) { [weak self] in
                let report = Self.buildAgeReport(for: folder)
                await MainActor.run {
                    guard let self else { return }
                    self.ageReports[path] = report
                    self.pendingReports.remove(path)
                }
            }
        }
    }

    private func topFolders(from root: FileNode, limit: Int) -> [FileNode] {
        Array(root.children.filter(\.isDirectory).sorted { $0.sizeOnDisk > $1.sizeOnDisk }.prefix(limit))
    }

    static func buildAgeReport(for folder: FileNode) -> AgeReport {
        var buckets = Array(repeating: Int64(0), count: 8)
        var months: [Int: [Int64]] = [:]
        var untouched: [FileNode] = []
        var untouchedTotal: Int64 = 0
        let now = Date().timeIntervalSince1970
        let year: Double = 365 * 24 * 3600

        var stack = folder.children
        while let node = stack.popLast() {
            guard !node.isDirectory else {
                stack.append(contentsOf: node.children)
                continue
            }
            let age = max(0, now - node.modifiedStamp)
            let bucket = ageBucket(age)
            buckets[bucket] += node.sizeOnDisk
            let month = monthNumber(node.modifiedStamp)
            months[month, default: Array(repeating: 0, count: 1)][0] += node.sizeOnDisk
            if age > year && node.sizeOnDisk > 40 * 1024 * 1024 {
                untouched.append(node)
                untouchedTotal += node.sizeOnDisk
            }
        }
        return AgeReport(buckets: buckets,
                         total: buckets.reduce(0, +),
                         months: months,
                         untouched: Array(untouched.sorted { $0.sizeOnDisk > $1.sizeOnDisk }.prefix(12)),
                         untouchedTotal: untouchedTotal)
    }

    private static func ageBucket(_ age: Double) -> Int {
        switch age {
        case ..<(30 * 24 * 3600): return 0        // < 30 days
        case ..<(90 * 24 * 3600): return 1
        case ..<(180 * 24 * 3600): return 2
        case ..<(365 * 24 * 3600): return 3
        case ..<(2 * 365 * 24 * 3600): return 4
        case ..<(3 * 365 * 24 * 3600): return 5
        case ..<(5 * 365 * 24 * 3600): return 6
        default: return 7
        }
    }

    private static func monthNumber(_ stamp: Double) -> Int {
        let date = Date(timeIntervalSince1970: stamp)
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return (comps.year ?? 1970) * 12 + (comps.month ?? 1)
    }

    // MARK: - Duplicates

    func findDuplicates() {
        guard let root, case .done = status, !isFindingDuplicates else { return }
        isFindingDuplicates = true
        duplicateGroups = []
        Task.detached(priority: .userInitiated) { [weak self] in
            let groups = DuplicateFinder.findDuplicates(in: root) { group in
                Task { @MainActor in
                    self?.duplicateGroups.append(group)
                }
            }
            await MainActor.run {
                self?.duplicateGroups = groups
                self?.isFindingDuplicates = false
            }
        }
    }

    // MARK: - Apps

    func loadInstalledApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        installedApps = []
        Task.detached(priority: .userInitiated) { [weak self] in
            var apps = AppUninstaller.loadInstalledApps { app in
                Task { @MainActor in
                    self?.installedApps.append(app)
                }
            }
            // Measure leftovers after listing ("Measuring apps and their
            // Library leftovers…").
            for i in apps.indices {
                apps[i].leftovers = AppUninstaller.findLeftovers(bundleIdentifier: apps[i].bundleIdentifier)
            }
            await MainActor.run {
                self?.installedApps = apps
                self?.isLoadingApps = false
            }
        }
    }

    // MARK: - Navigation

    func select(_ node: FileNode?) {
        selectedNode = node
        if let node, node.isDirectory {
            currentFolder = node
        }
    }

    func enter(folder: FileNode) {
        currentFolder = folder
        selectedNode = nil
    }

    func navigateUp() {
        if let parent = currentFolder?.parent {
            currentFolder = parent
        }
    }

    /// Live scanner counters surfaced to ScanningView.
    var scannedBytes: Int64 {
        guard let scanner else { return 0 }
        scanner.lock.lock()
        defer { scanner.lock.unlock() }
        return scanner.bytesScanned
    }

    var currentScanPath: String {
        guard let scanner else { return "" }
        scanner.lock.lock()
        defer { scanner.lock.unlock() }
        return scanner.currentPath
    }

    var filteredChildren: [FileNode] {
        guard let currentFolder else { return [] }
        let children = currentFolder.sortedChildren
        guard !filter.isEmpty else { return children }
        return children.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
}
