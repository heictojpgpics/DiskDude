//
//  TreemapView.swift
//  DiskDude
//
//  Reconstructed: squarified treemap with Cell model
//  (node, frame, color), cached layout, hover chips, tap-to-descend,
//  context menus, and abbreviatable labels.
//

import SwiftUI

struct TreemapView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovered: FileNode?
    @State private var cache = LayoutCache<CanvasKey, [Cell]>()

    struct Cell: Identifiable, Hashable {
        let node: FileNode
        var frame: CGRect
        var color: Color
        var id: ObjectIdentifier { node.id }
        static func == (l: Cell, r: Cell) -> Bool { l.node === r.node && l.frame == r.frame }
        func hash(into h: inout Hasher) { h.combine(node.id); h.combine(frame) }
    }

    var body: some View {
        GeometryReader { geo in
            let key = CanvasKey(
                layout: VizKey(generation: viewModel.generation,
                               node: folder.id,
                               width: Int(geo.size.width),
                               height: Int(geo.size.height),
                               depth: Int(viewModel.depth),
                               mode: viewModel.colorMode),
                width: Int(geo.size.width),
                height: Int(geo.size.height),
                selected: viewModel.selectedNode?.id,
                scheme: viewModel.colorSchemeActive,
                abbreviateLabels: viewModel.abbreviateLabels)

            let cells = cache.compute(key: key) {
                layout(root: folder, in: CGRect(origin: .zero, size: geo.size))
            }

            ZStack(alignment: .topLeading) {
                ForEach(cells) { cell in
                    cellView(cell)
                        .frame(width: cell.frame.width, height: cell.frame.height)
                        .position(x: cell.frame.midX, y: cell.frame.midY)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if let hovered {
                    HoverChip(node: hovered)
                        .offset(x: 14, y: 8)
                        .zIndex(2)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        let selected = viewModel.selectedNode === cell.node
        RoundedRectangle(cornerRadius: 3)
            .fill(cell.color.opacity(selected ? 1.0 : 0.88))
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(selected ? theme.text : theme.background.opacity(0.85), lineWidth: selected ? 2 : 1.2))
            .overlay(alignment: .topLeading) {
                if cell.frame.width > 44 && cell.frame.height > 18 {
                    Text(cell.node.name)
                        .font(.system(size: min(9.5, cell.frame.width / 11), weight: .semibold))
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .onTapGesture {
                if cell.node.isDirectory {
                    viewModel.enter(folder: cell.node)
                } else {
                    viewModel.select(cell.node)
                }
            }
            .onHover { over in
                hovered = over ? cell.node : nil
            }
            .contextMenu { NodeContextMenu(node: cell.node).environmentObject(viewModel) }
    }

    // MARK: - Squarified layout (Bruls, Huizing & van Wijk)

    private func layout(root: FileNode, in rect: CGRect) -> [Cell] {
        var out: [Cell] = []
        var queue: [(FileNode, CGRect, Int)] = [(root, rect, 0)]
        let maxDepth = Int(viewModel.depth)

        while let (node, r, depth) = queue.popLast() {
            guard r.width >= 2 && r.height >= 2 else { continue }
            if node.isDirectory && depth < maxDepth {
                let children = Array(node.sortedChildren.prefix(200))
                let rects = squarify(children: children, in: r)
                for (child, cr) in rects {
                    out.append(Cell(node: child, frame: cr, color: color(for: child, depth: depth + 1)))
                    if child.isDirectory && depth + 1 < maxDepth {
                        queue.append((child, cr, depth + 1))
                    }
                }
            } else {
                out.append(Cell(node: node, frame: r, color: color(for: node, depth: depth)))
            }
        }
        return out
    }

    private func squarify(children: [FileNode], in rect: CGRect) -> [(FileNode, CGRect)] {
        guard !children.isEmpty else { return [] }
        let total = children.reduce(0.0) { $0 + weight($1) }
        guard total > 0 else { return [] }

        var result: [(FileNode, CGRect)] = []
        var remaining = rect
        var items = children[...]
        var row: [FileNode] = []
        var rowWeight = 0.0
        let shortest = { min(remaining.width, remaining.height) }

        func placeRow() {
            guard !row.isEmpty, shortest() > 0 else { return }
            let fraction = rowWeight / total
            let along = (remaining.width >= remaining.height ? remaining.width : remaining.height) * fraction
            var offset = 0.0
            let horizontal = remaining.width >= remaining.height
            for node in row {
                let part = weight(node) / rowWeight * (horizontal ? remaining.height : remaining.width)
                let r = horizontal
                    ? CGRect(x: remaining.minX, y: remaining.minY + offset, width: along, height: part)
                    : CGRect(x: remaining.minX + offset, y: remaining.minY, width: part, height: along)
                result.append((node, r))
                offset += part
            }
            remaining = horizontal
                ? CGRect(x: remaining.minX + along, y: remaining.minY,
                         width: max(0, remaining.width - along), height: remaining.height)
                : CGRect(x: remaining.minX, y: remaining.minY + along,
                         width: remaining.width, height: max(0, remaining.height - along))
            row = []
            rowWeight = 0
        }

        while let node = items.first {
            let w = weight(node)
            let side = shortest()
            if row.isEmpty {
                row = [node]
                rowWeight = w
                items = items.dropFirst()
            } else {
                // Classic aspect test: does adding the node improve the worst ratio?
                let currentWorst = worstRatio(row: row, rowWeight: rowWeight, side: side)
                let newWorst = worstRatio(row: row + [node], rowWeight: rowWeight + w, side: side)
                if newWorst <= currentWorst {
                    row.append(node)
                    rowWeight += w
                    items = items.dropFirst()
                } else {
                    placeRow()
                }
            }
        }
        placeRow()
        return result
    }

    private func weight(_ node: FileNode) -> Double {
        max(1.0, Double(node.sizeOnDisk))
    }

    private func worstRatio(row: [FileNode], rowWeight: Double, side: Double) -> Double {
        guard rowWeight > 0, side > 0 else { return .infinity }
        var worst = 0.0
        for node in row {
            let fraction = weight(node) / rowWeight
            let along = side
            let across = fraction * side
            let ratio = max(along / max(across, 0.001), across / max(along, 0.001))
            worst = max(worst, ratio)
        }
        return worst
    }

    private func color(for node: FileNode, depth: Int) -> Color {
        switch viewModel.colorMode {
        case .type: return theme.categoryColor(node.category)
        case .folder: return theme.folderColor(depth: depth)
        case .age: return theme.ageColor(age: Date().timeIntervalSince1970 - node.modifiedStamp,
                                         maxAge: 365 * 24 * 3600 * 2)
        }
    }
}
