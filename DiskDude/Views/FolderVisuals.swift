//
//  FolderVisuals.swift
//  DiskDude
//
//  FolderGridView ("Browse folder by folder, sized as you go") with
//  FileTile, FolderCard (custom FolderShape), NodeContextMenu.
//

import SwiftUI
import AppKit

struct FolderGridView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            if viewModel.filteredChildren.isEmpty {
                VStack(spacing: 8) {
                    if viewModel.filter.isEmpty {
                        Text("This folder is empty.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        Text("Nothing here matches “\(viewModel.filter)”")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 10)], spacing: 10) {
                    ForEach(viewModel.filteredChildren, id: \.id) { node in
                        if node.isDirectory {
                            FolderCard(node: node,
                                       tint: cardTint(node),
                                       isSelected: viewModel.selectedNode === node)
                        } else {
                            FileTile(node: node, isSelected: viewModel.selectedNode === node)
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(theme.background)
    }

    private func cardTint(_ node: FileNode) -> Color {
        switch viewModel.colorMode {
        case .type: return theme.categoryColor(node.category)
        case .folder: return theme.folderColor(depth: node.depth)
        case .age: return theme.ageColor(age: Date().timeIntervalSince1970 - node.modifiedStamp,
                                         maxAge: 365 * 24 * 3600 * 2)
        }
    }
}

struct FolderCard: View {
    let node: FileNode
    let tint: Color
    let isSelected: Bool
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button {
            viewModel.enter(folder: node)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    FolderShape()
                        .fill(tint.opacity(0.9))
                        .frame(width: 30, height: 24)
                    Text(node.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                }
                HStack(spacing: 4) {
                    Text(formatBytes(node.sizeOnDisk))
                        .font(.system(size: 15, weight: .bold))
                    Text("· \(node.fileCount) files \(node.folderCount > 0 ? "· \(node.folderCount - 1) folders" : "")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
            }
            .padding(12)
            .background(CardBackground())
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(theme.ink, lineWidth: 2)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { NodeContextMenu(node: node).environmentObject(viewModel) }
        .simultaneousGesture(TapGesture().onEnded {
            viewModel.select(node)
        })
    }
}

struct FileTile: View {
    let node: FileNode
    let isSelected: Bool
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            viewModel.select(node)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.categoryColor(node.category))
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(theme.text)
                    Text(formatBytes(node.sizeOnDisk))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? theme.chip : theme.background))
            .overlay {
                if isSelected { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.ink, lineWidth: 1.6) }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { NodeContextMenu(node: node).environmentObject(viewModel) }
    }

    private var icon: String {
        switch node.category {
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.fill"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "doc.zipper"
        case .application: return "shippingbox.fill"
        case .system: return "gearshape"
        default: return "doc"
        }
    }
}

/// Rounded folder silhouette used by FolderCard.
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tab = rect.height * 0.22
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + tab,
                                    width: rect.width, height: rect.height - tab),
                         cornerSize: CGSize(width: rect.height * 0.18, height: rect.height * 0.18))
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.4, height: tab * 1.4),
                         cornerSize: CGSize(width: 2.5, height: 2.5))
        return p
    }
}

/// Context menu for any node: Quick Look, Reveal in Finder, copy path,
/// add/remove from cleanup queue (recovered menu strings).
struct NodeContextMenu: View {
    let node: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @EnvironmentObject private var queue: CleanupQueue

    var body: some View {
        let url = URL(fileURLWithPath: node.path)
        Group {
            Button("Preview") {
                QuickLookController.show(url: url)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelectingURLs([url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
            Divider()
            if queue.contains(url: url) {
                Button("Remove from cleanup") {
                    queue.remove(url: url)
                }
            } else {
                Button("Add to Cleanup Queue") {
                    queue.add(url: url, size: node.sizeOnDisk, reason: "Staged from Explore")
                }
            }
        }
    }
}
