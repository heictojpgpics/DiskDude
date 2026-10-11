//
//  ExploreView.swift
//  DiskDude
//
//  Reconstructed: mode strip with matched geometry (modeNamespace),
//  color-mode + depth controls, breadcrumb, then the active
//  visualization, plus the unreadable-folders notice.
//

import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @Namespace private var modeNamespace

    var body: some View {
        VStack(spacing: 0) {
            // Mode strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VisualizationMode.allCases) { mode in
                        modeButton(mode)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            Divider()

            HStack(spacing: 10) {
                breadcrumb
                Spacer()
                colorModePicker
                depthSlider
                abbreviateToggle
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            UnreadableFoldersNotice()

           visualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func modeButton(_ mode: VisualizationMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0)) {
                viewModel.mode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 10.5))
                Text(mode.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(viewModel.mode == mode ? theme.text : theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if viewModel.mode == mode {
                    Capsule().fill(theme.chip)
                        .matchedGeometryEffect(id: "mode", in: modeNamespace)
                }
            }
            .help(mode.caption)
        }
        .buttonStyle(.plain)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if let folder = viewModel.currentFolder, let parent = folder.parent {
                Button {
                    viewModel.navigateUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .buttonStyle(.plain)
                Text(folder.path)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else if let folder = viewModel.currentFolder {
                Text(folder.path)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var colorModePicker: some View {
        Picker("", selection: $viewModel.colorMode) {
            ForEach(ColorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .help("Color by type, folder, or age")
    }

    private var depthSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textTertiary)
            Slider(value: $viewModel.depth, in: 1...8, step: 1)
                .frame(width: 110)
            Text("\(Int(viewModel.depth))")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .help("How deep to draw")
    }

    private var abbreviateToggle: some View {
        Toggle(isOn: $viewModel.abbreviateLabels) {
            Text("Abbrev")
                .font(.system(size: 10.5))
        }
        .toggleStyle(.checkbox)
        .help("Abbreviate labels to initials")
    }

    @ViewBuilder
    private var visualization: some View {
        if let folder = viewModel.currentFolder ?? viewModel.root {
            switch viewModel.mode {
            case .treemap:
                TreemapView(folder: folder)
            case .folders:
                FolderGridView(folder: folder)
            case .sunburst:
                SunburstView(folder: folder)
            case .flame:
                FlameGraphView(folder: folder)
            case .bubbles:
                BubblesView(folder: folder)
            case .mindMap:
                MindMapView(folder: folder)
            case .topSizes:
                TopSizesView(folder: folder)
            case .ageMap:
                AgeMapView(folder: folder)
            case .outline:
                OutlineListView(folder: folder)
            }
        }
    }
}
