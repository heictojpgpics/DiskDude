//
//  SidebarAndTasks.swift
//  DiskDude
//
//  Reconstructed: SidebarView (recent scans navigation) and TaskKey
//  (async task dedup for Top Sizes rebuilds).
//

import SwiftUI

/// Sidebar listing recent scan roots (part of the navigation chrome).
struct SidebarView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Recent scans", trailing: nil)
            ForEach(viewModel.recents, id: \.self) { url in
                Button {
                    viewModel.scan(root: url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                        Text(url.lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(viewModel.root?.rootPath == url.path ? theme.chip : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Macintosh HD")
                    .font(.system(size: 10.5, weight: .semibold))
                SegmentedBar(segments: [Double(viewModel.disk.used), Double(viewModel.disk.free)],
                             total: Double(max(1, viewModel.disk.total)))
            }
            .padding(10)
            .background(CardBackground())
        }
        .padding(12)
        .frame(width: 200)
        .background(theme.panel)
    }
}

/// Identifies a Top Sizes rebuild task so stale rankings are dropped
/// (recovered struct TaskKey: folder, scope, generation).
struct TaskKey: Hashable {
    var folder: ObjectIdentifier
    var scope: TopSizesView.Scope
    var generation: Int
}
