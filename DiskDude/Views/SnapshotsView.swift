//
//  SnapshotsView.swift
//  DiskDude
//
//  Reconstructed: snapshot list, "Take Snapshot Now", before/after
//  comparison (Comparison enum: ready/loading/failed/differentRoots)
//  with recovered strings.
//

import SwiftUI

struct SnapshotsView: View {
    @EnvironmentObject private var viewModel: ScanViewModel

    var body: some View {
        SnapshotsContent()
    }
}

struct SnapshotsContent: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @ObservedObject private var store = viewModel.snapshotStore
    @Environment(\.theme) private var theme
    @State private var beforeID: Snapshot.Summary.ID?
    @State private var afterID: Snapshot.Summary.ID?
    @State private var comparison: Comparison?

    enum Comparison: Equatable {
        case ready([Snapshot.Delta])
        case loading
        case failed
        case differentRoots
    }

    var body: some View {
        Group {
            if store.summaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 35))
                        .foregroundStyle(theme.textTertiary)
                    Text("No snapshots yet. Take one after a scan, then compare it to a later scan.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: 380)
                        .multilineTextAlignment(.center)
                    if viewModel.root != nil {
                        OutlineButton(title: "Take Snapshot Now",
                                      systemImage: "camera",
                                      height: 34, fontSize: 12) {
                            takeSnapshot()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        SectionCaption(title: "Snapshots", trailing: "\(store.summaries.count) saved")
                        Spacer()
                        if viewModel.root != nil {
                            OutlineButton(title: "Take Snapshot Now",
                                          systemImage: "camera",
                                          height: 30, fontSize: 11) {
                                takeSnapshot()
                            }
                        }
                    }
                    .padding(14)

                    Picker("Before", selection: Binding(
                        get: { beforeID ?? store.summaries.first?.id },
                        set: { beforeID = $0; compare() })) {
                        ForEach(store.summaries) { s in
                            Text(label(s)).tag(s.id as Snapshot.Summary.ID?)
                        }
                    }
                    .frame(width: 320)

                    Picker("After", selection: Binding(
                        get: { afterID ?? store.summaries.last?.id },
                        set: { afterID = $0; compare() })) {
                        ForEach(store.summaries) { s in
                            Text(label(s)).tag(s.id as Snapshot.Summary.ID?)
                        }
                    }
                    .frame(width: 320)

                    comparisonBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.background)
    }

    @ViewBuilder
    private var comparisonBody: some View {
        switch comparison {
        case .loading:
            ProgressView().padding(.top, 40)
        case .failed:
            Text("Couldn't read one of these snapshots.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 40)
        case .differentRoots:
            Text("These snapshots are of different folders. Pick two of the same folder.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 40)
        case .ready(let deltas):
            if deltas.isEmpty {
                Text("No folder changed size.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 40)
            } else {
                List {
                    ForEach(deltas) { d in
                        HStack {
                            Text(d.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Text(formatBytes(d.before))
                                .foregroundStyle(theme.textTertiary)
                            Text("→")
                                .foregroundStyle(theme.textTertiary)
                            Text(formatBytes(d.after))
                            Image(systemName: d.grew ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundStyle(d.grew ? .red : .green)
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
                .listStyle(.inset)
            }
        case nil:
            Text("Pick a Before and an After snapshot to see what grew.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 40)
        }
    }

    private func label(_ s: Snapshot.Summary) -> String {
        "\(s.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(s.rootPath)"
    }

    private func takeSnapshot() {
        guard let root = viewModel.root else { return }
        let snap = SnapshotStore.snapshot(from: root)
        store.save(snap)
    }

    private func compare() {
        guard let beforeID, let afterID,
              let before = store.summaries.first(where: { $0.id == beforeID }),
              let after = store.summaries.first(where: { $0.id == afterID }) else {
            comparison = nil
            return
        }
        comparison = .loading
        Task.detached(priority: .userInitiated) {
            guard let b = store.load(before), let a = store.load(after) else {
                await MainActor.run { self.comparison = .failed }
                return
            }
            guard b.rootPath == a.rootPath else {
                await MainActor.run { self.comparison = .differentRoots }
                return
            }
            let deltas = SnapshotStore.compare(b, a)
            await MainActor.run { self.comparison = .ready(deltas) }
        }
    }
}

// MARK: - Cleanup queue sheet

struct CleanupQueueView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @ObservedObject private var queue: CleanupQueue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var showConfirm = false
    @State private var failures: [URL] = []

    init() {
        queue = CleanupQueue.sharedGlobal
    }

    init(queue: CleanupQueue) {
        self.queue = queue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionCaption(title: "Staged for Cleanup",
                               trailing: formatBytes(queue.totalSize))
                Spacer()
                SquareIconButton(systemImage: "xmark", label: "Close", size: 12) {
                    dismiss()
                }
            }
            .padding(14)

            Divider()

            if queue.items.isEmpty {
                Text("Nothing staged yet. Stage items from any visualization, Quick Wins, Duplicates, or App Uninstaller.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: 380)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(queue.items) { item in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(theme.categoryColor(.other))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(item.reason)
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Text(formatBytes(item.size))
                                .font(.system(size: 11).monospacedDigit())
                            Button("Remove from cleanup") {
                                queue.remove(url: item.url)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Text("\(queue.count) items · \(formatBytes(queue.totalSize))")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    OutlineButton(title: "Move to Trash…",
                                  systemImage: "trash.fill",
                                  height: 32, fontSize: 12) {
                        showConfirm = true
                    }
                }
                .padding(14)
                .alert("Move \(queue.count) items to Trash?", isPresented: $showConfirm) {
                    Button("Move to Trash", role: .destructive) {
                        emptyQueueToTrash()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This frees \(formatBytes(queue.totalSize)). Items go to the Trash, not permanent deletion — you can still recover them from there.")
                }
            }

            if !failures.isEmpty {
                Text("\(failures.count) item(s) couldn't be moved to the Trash:\n\(failures.map(\.lastPathComponent).joined(separator: "\n"))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .padding(14)
                Text("\(failures.count) item(s) — check permissions.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
            }
        }
        .frame(width: 560, height: 480)
    }

    private func emptyQueueToTrash() {
        Task {
            let (moved, failed) = await queue.moveToTrash()
            failures = failed.map(\.url)
            if failed.isEmpty { dismiss() }
            _ = moved
        }
    }
}

/// Badge button in the top bar showing the staged count.
struct CleanupBadgeButton: View {
    @ObservedObject private var queue = CleanupQueue.sharedGlobal
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .medium))
                if queue.count > 0 {
                    Text("\(queue.count)")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.ink))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: queue.count > 0 ? nil : 26, height: 26)
            .padding(.horizontal, queue.count > 0 ? 4 : 0)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.chip))
        }
        .buttonStyle(.plain)
        .disabled(queue.count == 0)
        .opacity(queue.count == 0 ? 0.45 : 1)
    }
}

// MARK: - Quick wins

struct QuickWinRow: View {
    let win: QuickWins.Category
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(theme.ink)
                Text(win.kind.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(win.matches.count == 1 ? "1 item" : "\(win.matches.count) items")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                Text(formatBytes(win.totalSize))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            ForEach(win.matches.prefix(6), id: \.id) { node in
                HStack {
                    Text(node.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Add to Cleanup Queue") {
                        viewModel.cleanupQueue.add(url: URL(fileURLWithPath: node.path),
                                                   size: node.sizeOnDisk,
                                                   reason: "Staged for Cleanup")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(CardBackground())
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch win.kind {
        case .downloads: return "arrow.down.circle.fill"
        case .caches: return "xmark.circle.fill"
        case .simulators: return "iphone"
        case .largeMedia: return "film.fill"
        case .nodeModules: return "chevron.left.forwardslash.chevron.right"
        case .buildArtifacts: return "hammer.fill"
        case .derivedData: return "cube.fill"
        }
    }
}

// MARK: - Unreadable notice

struct UnreadableFoldersNotice: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        if viewModel.showAccessNotice {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.unreadableFolderCount) folders couldn't be read — sizes may be incomplete")
                        .font(.system(size: 11, weight: .semibold))
                    if !viewModel.unreadableFolderSamples.isEmpty {
                        Text("macOS denied access. Granting Full Disk Access includes privacy-protected locations; folders owned by the system or other users stay unreadable.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer()
                if let first = viewModel.unreadableFolderSamples.first {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelectingURLs([URL(fileURLWithPath: first)])
                    }
                    .font(.system(size: 10.5))
                    .buttonStyle(.link)
                }
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 10.5))
                .buttonStyle(.link)
                SquareIconButton(systemImage: "xmark", label: "Dismiss", size: 11) {
                    viewModel.showAccessNotice = false
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.chip)
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let node = viewModel.selectedNode ?? viewModel.currentFolder {
                InspectorContent(node: node)
            } else {
                Text("Select an item to inspect it.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.panel)
    }
}

struct InspectorContent: View {
    let node: FileNode
    @ObservedObject private var queue = CleanupQueue.sharedGlobal
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(theme.categoryColor(node.category))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(2)
                        Text(node.isDirectory ? "Folder" : node.category.label)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Divider()

                row("Size on disk", formatBytes(node.sizeOnDisk))
                row("Logical size", formatBytes(node.logicalSize))
                if let modified = Date(timeIntervalSince1970: node.modifiedStamp) as Date? {
                    row("Modified", modified.formatted(date: .abbreviated, time: .shortened))
                }
                if node.createdStamp > 0, let created = Date(timeIntervalSince1970: node.createdStamp) {
                    row("Created", created.formatted(date: .abbreviated, time: .shortened))
                }
                if node.isDirectory {
                    row("Files", "\(node.fileCount)")
                    row("Folders", "\(node.folderCount - 1)")
                }

                Divider()

                if let sizes = node.typeSizes, node.isDirectory {
                    SectionCaption(title: "By type", trailing: nil)
                    ForEach(FileCategory.allCases) { cat in
                        let v = sizes[safe: cat.rawValue] ?? 0
                        if v > 0 {
                            HStack {
                                Circle().fill(theme.categoryColor(cat)).frame(width: 7, height: 7)
                                Text(cat.label).font(.system(size: 10.5))
                                Spacer()
                                Text(formatBytes(v))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        SquareIconButton(systemImage: "play.rectangle.fill", label: "Quick Look", size: 11) {
                            QuickLookController.show(url: URL(fileURLWithPath: node.path))
                        }
                        SquareIconButton(systemImage: "arrow.up.forward.square", label: "Reveal in Finder", size: 11) {
                            NSWorkspace.shared.activateFileViewerSelectingURLs([URL(fileURLWithPath: node.path)])
                        }
                        SquareIconButton(systemImage: "doc.on.clipboard.fill", label: "Copy path", size: 11) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(node.path, forType: .string)
                        }
                    }
                    let url = URL(fileURLWithPath: node.path)
                    if queue.contains(url: url) {
                        OutlineButton(title: "Remove from cleanup",
                                      systemImage: "trash.fill",
                                      height: 30, fontSize: 11,
) {
                            queue.remove(url: url)
                        }
                    } else {
                        InkButton(title: "Add to Cleanup Queue",
                                  systemImage: "shippingbox.fill",
                                  height: 30, fontSize: 11) {
                            queue.add(url: url, size: node.sizeOnDisk, reason: "Staged for Cleanup")
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }
}
