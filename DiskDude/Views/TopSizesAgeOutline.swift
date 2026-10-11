//
//  TopSizesAgeOutline.swift
//  DiskDude
//
//  TopSizesView ("The biggest items, ranked" — Scope: files/folders,
//  "Biggest files anywhere"/"Biggest folders anywhere"),
//  AgeMapView + UntouchedCard + MonthHeatmapCard + AgeBucketsCard,
//  OutlineListView.
//

import SwiftUI

struct TopSizesView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case files
        case folders
        var id: String { rawValue }
        var title: String { self == .files ? "Biggest files anywhere" : "Biggest folders anywhere" }
    }
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var scope: Scope = .files
    @Namespace private var scopeNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        Text(s == .files ? "Files" : "Folders").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
            }
            .padding(14)

            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, node in
                        TopSizeRow(rank: index + 1,
                                   node: node,
                                   fraction: fraction(of: node),
                                   share: share(of: node),
                                   showsLocation: true)
                    }
                } header: {
                    SectionCaption(title: scope.title,
                                   trailing: "\(rows.count) items")
                }
            }
            .listStyle(.inset)
        }
        .background(theme.background)
    }

    private var rows: [FileNode] {
        scope == .files ? viewModel.rankings.files : viewModel.rankings.folders
    }

    private var maxBytes: Int64 { rows.first?.sizeOnDisk ?? 1 }

    private func fraction(of node: FileNode) -> Double {
        maxBytes > 0 ? Double(node.sizeOnDisk) / Double(maxBytes) : 0
    }

    private func share(of node: FileNode) -> String {
        guard let root = viewModel.root, root.sizeOnDisk > 0 else { return "" }
        return formatPercentage(node.sizeOnDisk, of: root.sizeOnDisk)
    }
}

struct TopSizeRow: View {
    let rank: Int
    let node: FileNode
    let fraction: Double
    let share: String
    let showsLocation: Bool
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 22, alignment: .trailing)
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.categoryColor(node.category))
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if showsLocation {
                    Text(node.path)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track)
                        Capsule().fill(theme.categoryColor(node.category))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 5)
            }
            Text(share)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 46, alignment: .trailing)
            Text(formatBytes(node.sizeOnDisk))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(node) }
        .contextMenu { NodeContextMenu(node: node).environmentObject(viewModel) }
    }
}

// MARK: - Age map

struct AgeMapView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionCaption(title: "How old are these bytes?",
                               trailing: nil)
                if viewModel.pendingReports.contains(folder.path) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading modification dates…")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                } else if let report = viewModel.ageReports[folder.path] {
                    AgeBucketsCard(report: report)
                    MonthHeatmapCard(report: report)
                    UntouchedCard(report: report)
                } else {
                    Text("Run a scan first.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(theme.background)
    }
}

struct AgeBucketsCard: View {
    let report: AgeReport
    @Environment(\.theme) private var theme

    private let labels = ["<30d", "30–90d", "90–180d", "180d–1y", "1–2y", "2–3y", "3–5y", "5y+"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Bytes by last-modified month",
                           trailing: formatBytes(report.total))
            HStack(spacing: 6) {
                ForEach(Array(zip(labels.indices, labels)), id: \.0) { i, label in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(theme.track)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.ageColor(age: Double(i) * 180 * 24 * 3600, maxAge: 5 * 365 * 24 * 3600))
                                    .frame(height: max(3, geo.size.height * fraction(i)))
                            }
                        }
                        .frame(height: 60)
                        Text(label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(CardBackground())
    }

    private func fraction(_ i: Int) -> Double {
        guard report.total > 0 else { return 0 }
        return Double(report.buckets[safe: i] ?? 0) / Double(report.total)
    }
}

struct MonthHeatmapCard: View {
    let report: AgeReport
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Bytes by last-modified month",
                           trailing: "\(report.months.count) months")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 12), spacing: 3) {
                let months = sortedMonths
                let maxVal = months.values.max() ?? 1
                ForEach(months.keys.sorted(), id: \.self) { m in
                    let v = months[m] ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.ageColor(age: age(of: m), maxAge: 5 * 365 * 24 * 3600))
                        .frame(height: 16)
                        .opacity(maxVal > 0 ? 0.35 + 0.65 * Double(v) / Double(maxVal) : 0.3)
                        .help(monthName(m))
                }
            }
        }
        .padding(14)
        .background(CardBackground())
    }

    private var sortedMonths: [Int: Int64] {
        var out: [Int: Int64] = [:]
        for (m, v) in report.months {
            out[m] = v.first ?? 0
        }
        return out
    }

    private func age(of month: Int) -> Double {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let nowM = (now.year ?? 1970) * 12 + (now.month ?? 1)
        return Double((nowM - month)) * 30 * 24 * 3600
    }

    private func monthName(_ m: Int) -> String {
        let year = m / 12, month = m % 12
        let names = Calendar.current.monthSymbols
        return "\(names[max(0, month - 1)]) \(year)"
    }
}

struct UntouchedCard: View {
    let report: AgeReport
    @ObservedObject private var queue = CleanupQueue.sharedGlobal
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Big & untouched for a year",
                           trailing: formatBytes(report.untouchedTotal))
            if report.untouched.isEmpty {
                Text("Nothing over 40 MB has sat untouched for a year here.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(report.untouched, id: \.id) { node in
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                        Text(node.path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(formatBytes(node.sizeOnDisk))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                        Button(queue.contains(url: URL(fileURLWithPath: node.path)) ? "Remove from cleanup" : "Add to Cleanup Queue") {
                            queue.toggle(url: URL(fileURLWithPath: node.path),
                                         size: node.sizeOnDisk,
                                         reason: "Staged for Cleanup")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(14)
        .background(CardBackground())
    }
}

// MARK: - Outline list

struct OutlineListView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var expanded: Set<ObjectIdentifier> = []

    var body: some View {
        List {
            outlineSection(node: folder, level: 0)
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .background(theme.background)
    }

    @ViewBuilder
    private func outlineSection(node: FileNode, level: Int) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(node.id) },
            set: { on in
                if on { expanded.insert(node.id) } else { expanded.remove(node.id) }
            })) {
            ForEach(node.sortedChildren, id: \.id) { child in
                outlineSection(node: child, level: level + 1)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.categoryColor(node.category))
                Text(node.name)
                    .font(.system(size: 11, weight: node.isDirectory ? .semibold : .regular))
                Spacer()
                Text(formatBytes(node.sizeOnDisk))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                Text("\(node.fileCount) files")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 70, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.select(node) }
            .contextMenu { NodeContextMenu(node: node).environmentObject(viewModel) }
        }
    }
}

/// Shared cleanup queue instance for views without an explicit
/// EnvironmentObject injection.
extension CleanupQueue {
    static let sharedGlobal = CleanupQueue()
}
