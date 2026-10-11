//
//  MonitorView.swift
//  DiskDude
//
//  Reconstructed: live CPU/memory/network/process monitor with
//  sparkline histories (cpuHistory, memoryHistory, freeSpaceHistory
//  State arrays), VolumeInfo list, SegmentedBar, MonitorCard,
//  process table with cpu/memory sort.
//

import SwiftUI

struct MonitorView: View {
    enum ProcessSort: String, CaseIterable, Identifiable {
        case cpu
        case memory
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var snapshot = SystemMonitor.Snapshot()
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    @State private var freeSpaceHistory: [Double] = []
    @State private var volumes: [VolumeInfo] = []
    @State private var storageExpanded = false
    @State private var processSort: ProcessSort = .cpu

    private let state = SystemMonitor.State()
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MonitorCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "Pressure over time", trailing: nil)
                            Text(String(format: "%.1f%%", snapshot.cpu.user + snapshot.cpu.system))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            SegmentedBar(segments: [
                                snapshot.cpu.user, snapshot.cpu.system, snapshot.cpu.idle,
                            ], total: 100)
                            Text("Load \(snapshot.cpu.loadAverage, specifier: "%.2f")")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    MonitorCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "Memory", trailing: nil)
                            UsageRing(fraction: snapshot.memory.pressure, lineWidth: 6)
                                .frame(width: 54, height: 54)
                            Text("\(formatBytes(snapshot.memory.used)) of \(formatBytes(snapshot.memory.total))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 12) {
                    MonitorCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "Free space over time", trailing: nil)
                            Sparkline(values: freeSpaceHistory, color: theme.ink, maxValue: nil)
                                .frame(height: 44)
                            Text("\(formatBytes(viewModel.disk.free)) free of \(formatBytes(viewModel.disk.total))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textSecondary)
                            if !storageExpanded {
                                Button("Show more volumes") {
                                    withAnimation(.easeOut(duration: 0.15)) { storageExpanded = true }
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(.link)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    MonitorCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "Network", trailing: nil)
                            HStack(spacing: 16) {
                                stat("↓", snapshot.network.downBytesPerSec, theme.ink)
                                stat("↑", snapshot.network.upBytesPerSec, theme.categoryColor(.audio))
                            }
                            Text("Session: ↓ \(formatBytes(snapshot.network.sessionDown)) · ↑ \(formatBytes(snapshot.network.sessionUp))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if storageExpanded {
                    MonitorCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SectionCaption(title: "Volumes", trailing: nil)
                                Spacer()
                                Button("Show fewer volumes") {
                                    withAnimation(.easeOut(duration: 0.15)) { storageExpanded = false }
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(.link)
                            }
                            ForEach(volumes) { v in
                                HStack {
                                    Image(systemName: "internaldrive.fill")
                                        .font(.system(size: 10.5))
                                    Text(v.name).font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    UsageRing(fraction: v.total > 0 ? Double(v.total - v.free) / Double(v.total) : 0, lineWidth: 3)
                                        .frame(width: 20, height: 20)
                                    Text("\(formatBytes(v.free)) free")
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                        }
                        .padding(14)
                    }
                }

                MonitorCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionCaption(title: "TOP PROCESSES BY \(processSort == .cpu ? "CPU" : "Memory")",
                                           trailing: "\(snapshot.processCount) processes")
                            Spacer()
                            Picker("", selection: $processSort) {
                                ForEach(ProcessSort.allCases) { s in
                                    Text(s == .cpu ? "CPU" : "Memory").tag(s)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                        HStack(spacing: 8) {
                            TextField("Filter processes", text: $processSearch)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                        }
                        ForEach(sortedProcesses) { proc in
                            HStack(spacing: 8) {
                                Text(proc.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if processSort == .cpu {
                                    Text(proc.cpuPercent, format: .number.precision(.fractionLength(1)))
                                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                                        .frame(width: 60, alignment: .trailing)
                                    Text("%")
                                        .font(.system(size: 9))
                                } else {
                                    Text(formatBytes(proc.memoryBytes))
                                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                }
                            }
                        }
                        if sortedProcesses.isEmpty {
                            Text("No matching processes")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(14)
                }
            }
            .padding(14)
        }
        .background(theme.background)
        .onReceive(timer) { _ in
            let snap = SystemMonitor.sample(state: state)
            snapshot = snap
            appendCapped(&cpuHistory, 100 - snap.cpu.idle)
            appendCapped(&memoryHistory, snap.memory.pressure * 100)
            appendCapped(&freeSpaceHistory, Double(viewModel.disk.free))
        }
        .onAppear {
            refreshVolumes()
        }
    }

    @State private var processSearch = ""
    @State private var processesExpanded = false

    private var sortedProcesses: [SystemMonitor.ProcessStat] {
        let base = processSort == .cpu
            ? snapshot.topProcessesByCPU
            : snapshot.topProcessesByMemory
        guard !processSearch.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(processSearch) }
    }

    private func stat(_ arrow: String, _ perSec: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(arrow).font(.system(size: 13, weight: .bold))
                Text(formatBytes(Int64(perSec * 2)) + "/s")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(color)
        }
    }

    private func appendCapped(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > 90 { arr.removeFirst(arr.count - 90) }
    }

    private func refreshVolumes() {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys),
                  v.isVolume ?? false,
                  let name = v.volumeName else { return nil }
            return VolumeInfo(url: url, name: name,
                              total: Int64(v.volumeTotalCapacity ?? 0),
                              free: Int64(v.volumeAvailableCapacity ?? 0))
        }
    }
}

struct VolumeInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    var id: String { url.absoluteString }
}

struct SegmentedBar: View {
    let segments: [Double]
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, v in
                    Rectangle()
                        .fill(Color(hue: Double(i) / Double(max(1, segments.count)), saturation: 0.6, brightness: 0.85))
                        .frame(width: total > 0 ? geo.size.width * (v / total) : 0)
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double?

    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard values.count > 1 else { return }
                let maxV = maxValue ?? (values.max() ?? 1)
                let step = geo.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat(maxV > 0 ? v / maxV : 0))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct MonitorCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .background(CardBackground())
    }
}
