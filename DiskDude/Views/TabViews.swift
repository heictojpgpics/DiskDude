//
//  TabViews.swift
//  DiskDude
//
//  DuplicatesView, AppUninstallerView (AppRow, VersionChip) —
//  behavior + strings recovered ("Scan for Duplicates",
//  "Keep this, stage the rest", "No apps found in /Applications.",
//  privacy URL for AppBundles, uninstall confirm text).
//

import SwiftUI
import AppKit

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if viewModel.isFindingDuplicates {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Scanning for duplicates…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.duplicateGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 35))
                        .foregroundStyle(theme.textTertiary)
                    if viewModel.root == nil {
                        Text("Run a scan first.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        Text("No duplicate scan yet, or none found.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textTertiary)
                    }
                    if viewModel.root != nil {
                        OutlineButton(title: "Scan for Duplicates",
                                      systemImage: "magnifyingglass",
                                      height: 34, fontSize: 12) {
                            viewModel.findDuplicates()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let totalWasted = viewModel.duplicateGroups.reduce(Int64(0)) { $0 + $1.wasted }
                    Section {
                        ForEach(viewModel.duplicateGroups) { group in
                            DuplicateGroupRow(group: group)
                        }
                    } header: {
                        SectionCaption(title: "Duplicates",
                                       trailing: "\(formatBytes(totalWasted)) could be reclaimed across \(viewModel.duplicateGroups.count) groups")
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(theme.background)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateFinder.Group
    @ObservedObject private var queue = CleanupQueue.sharedGlobal
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(group.files.count) identical files · \(formatBytes(group.size)) each · wastes \(formatBytes(group.wasted))")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Keep this, stage the rest") {
                    let keep = group.files.first
                    for file in group.files.dropFirst() {
                        queue.add(url: URL(fileURLWithPath: file.path),
                                  size: file.sizeOnDisk,
                                  reason: "Staged for Cleanup")
                    }
                }
                .font(.system(size: 10.5, weight: .semibold))
                .buttonStyle(.borderless)
            }
            ForEach(group.files, id: \.id) { file in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.categoryColor(file.category))
                    Text(file.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button(queue.contains(url: URL(fileURLWithPath: file.path)) ? "Remove" : "Add to Cleanup Queue") {
                        queue.toggle(url: URL(fileURLWithPath: file.path),
                                     size: file.sizeOnDisk,
                                     reason: "Staged for Cleanup")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - App uninstaller

struct AppUninstallerView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var expanded: Set<UUID> = []
    @State private var pendingUninstall: AppUninstaller.InstalledApp?
    @State private var uninstallingID: UUID?
    @State private var failure: (app: String, urls: [URL])?

    var body: some View {
        Group {
            if viewModel.isLoadingApps && viewModel.installedApps.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Measuring apps and their Library leftovers…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.installedApps.isEmpty {
                VStack(spacing: 10) {
                    Text("No apps found in /Applications.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textTertiary)
                    OutlineButton(title: "Reload Apps",
                                  systemImage: "arrow.clockwise",
                                  height: 32, fontSize: 12) {
                        viewModel.loadInstalledApps()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(viewModel.installedApps) { app in
                            AppRow(app: app,
                                   isExpanded: expanded.contains(app.id),
                                   isUninstalling: uninstallingID == app.id) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expanded.contains(app.id) { expanded.remove(app.id) }
                                    else { expanded.insert(app.id) }
                                }
                            } uninstall: {
                                confirmUninstall(app)
                            }
                        }
                    } header: {
                        SectionCaption(title: "Applications",
                                       trailing: "\(viewModel.installedApps.count) apps")
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(theme.background)
        .alert("Uninstall \(pendingUninstall?.displayName ?? "app")?", isPresented: Binding(
            get: { pendingUninstall != nil },
            set: { if !$0 { pendingUninstall = nil } })) {
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
            Button("Move to Trash", role: .destructive) {
                if let app = pendingUninstall { runUninstall(app) }
                pendingUninstall = nil
            }
        } message: {
            Text("The app and \(pendingUninstall?.leftovers.reduce(0) { $0 + $1.urls.count } ?? 0) leftover item(s) — \(pendingUninstall.map { formatBytes($0.leftovers.reduce(0) { $0 + Int64($1.totalSize) }) } ?? "") — go to the Trash. The app is quit first if it's running.")
        }
        .alert("Couldn't fully uninstall \(failure?.app ?? "")", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }), presenting: failure) { failure in
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text("\(failure.urls.count) item(s) couldn't be moved to the Trash:\n\(failure.urls.prefix(5).map(\.path).joined(separator: "\n"))\n\nAllow this app under Privacy & Security → App Management (or Full Disk Access), then try again.")
        }
    }

    private func confirmUninstall(_ app: AppUninstaller.InstalledApp) {
        pendingUninstall = app
    }

    private func runUninstall(_ app: AppUninstaller.InstalledApp) {
        uninstallingID = app.id
        Task.detached(priority: .userInitiated) {
            let failed = AppUninstaller.uninstall(app)
            await MainActor.run {
                uninstallingID = nil
                if !failed.isEmpty {
                    failure = (app: app.displayName, urls: failed)
                } else {
                    viewModel.loadInstalledApps()
                }
            }
        }
    }
}

struct AppRow: View {
    let app: AppUninstaller.InstalledApp
    let isExpanded: Bool
    let isUninstalling: Bool
    let toggle: () -> Void
    let uninstall: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        if let version = app.version {
                            VersionChip(text: version)
                        }
                    }
                    Text("· last used \(relativeDateText(app.lastUsedDate))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Button(action: uninstall) {
                    if isUninstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Uninstall")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isUninstalling)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(theme.textTertiary)
                    .onTapGesture(perform: toggle)
            }
            if isExpanded {
                ForEach(app.leftovers) { group in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                        Text(group.category)
                            .font(.system(size: 11, weight: .medium))
                        Text("\(group.urls.count) items · \(formatBytes(group.totalSize))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                    }
                    .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 4)
        .background(hovering ? theme.chip.opacity(0.5) : .clear)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

struct VersionChip: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.chip))
            .foregroundStyle(theme.textTertiary)
    }
}
