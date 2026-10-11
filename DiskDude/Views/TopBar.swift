//
//  TopBar.swift
//  DiskDude
//
//  Reconstructed: matched-geometry tab bar (tabNamespace), volume chip,
//  search field (FocusState), inspector toggle, cleanup badge button.
//

import SwiftUI

struct TopBar: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @Namespace private var tabNamespace
    @State private var showQueue = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Volume usage chip
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.disk.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(formatBytes(viewModel.disk.used)) of \(formatBytes(viewModel.disk.total))")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                }
                UsageRing(fraction: viewModel.disk.usedFraction, lineWidth: 3)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.chip))

            // Tabs with matched geometry
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab)
                }
            }

            Spacer()

            // Filter field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
                TextField("Filter by name...", text: $viewModel.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !viewModel.filter.isEmpty {
                    Button {
                        viewModel.filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.chip))
            .frame(width: 200)

            // Quick look toggle
            SquareIconButton(systemImage: "play.rectangle.fill",
                             label: "Preview the selected file",
                             size: 13) {
                QuickLookController.show(url: viewModel.selectedNode.map { URL(fileURLWithPath: $0.path) })
            }

            // Inspector toggle ("Show or hide the inspector")
            SquareIconButton(systemImage: viewModel.showInspector ? "macwindow.badge.plus" : "macwindow",
                             label: "Show or hide the inspector",
                             size: 13) {
                viewModel.showInspector.toggle()
            }

            // Theme toggle
            SquareIconButton(systemImage: viewModel.themeName == .dark ? "sun.max.fill" : "moon.fill",
                             label: viewModel.themeName == .dark ? "Switch to light theme" : "Switch to dark theme",
                             size: 13) {
                viewModel.themeName = viewModel.themeName == .dark ? .light : .dark
            }

            // Cleanup queue badge
            CleanupBadgeButton {
                showQueue = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.background)
        .onAppear { showQueue = false }
        .sheet(isPresented: $showQueue) {
            CleanupQueueView()
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.tab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(viewModel.tab == tab ? theme.text : theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if viewModel.tab == tab {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.chip)
                        .matchedGeometryEffect(id: "tab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
