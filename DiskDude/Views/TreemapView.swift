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
    @State private var cache = LayoutCache<VizKey, [Cell]>()

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
            let vizKey = VizKey(generation: viewModel.generation,
                                node: folder.id,
                                width: Int(geo.size.width),
                                height: Int(geo.size.height),
                                depth: Int(viewModel.depth),
                                mode: viewModel.colorMode)
            let cells = cache.compute(key: vizKey) {
                layout(root: folder, in: CGRect(origin: .zero, size: geo.size))
            }
            CachedCanvas(key: CanvasKey(layout: vizKey,
                                        width: Int(geo.size.width),
                                        height: Int(geo.size.height),
                                        selected: viewModel.selectedNode?.id,
                                        scheme: viewModel.colorSchemeActive,
                                        abbreviateLabels: viewModel.abbreviateLabels)) { context, size in
                draw(context: context, size: size, cells: cells)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let cell = cells.last(where: { $0.frame.contains(location) }) {
                    if cell.node.isDirectory {
                        viewModel.enter(folder: cell.node)
                    } else {
                        viewModel.select(cell.node)
                    }
                }
            }
            .onHover { over in
                hovered = nil
            }
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

    /// Canvas rendering (recovered byte-level from the binary's
    /// GraphicsContext calls): container panel with 0.5pt inset and 8pt
    /// continuous corners; file tiles fill at 0.85 opacity with
    /// min(4, side/2) radius; folder tiles fill at 0.4 plus a
    /// 1pt black-6% stroke with min(5, side/2) radius; the selected tile
    /// gets a 1.5pt ink stroke; labels are Text drawn at points with the
    /// (width - 12) / 6 size heuristic capped at 9.5 and skipped under
    /// 58×22pt or fewer than 3 units of space.
    private func draw(context: GraphicsContext, size: CGSize, cells: [Cell]) {
        let bounds = CGRect(origin: .zero, size: size)
        // container panel
        let container = Path(roundedRect: bounds.insetBy(0.5, 0.5),
                             cornerRadius: 8, style: .continuous)
        context.fill(container, with: .color(theme.panel))
        context.stroke(container, with: .color(theme.border), lineWidth: 1)

        for cell in cells {
            let radius = min(cell.node.isDirectory ? 5.0 : 4.0,
                             min(cell.frame.width, cell.frame.height) * 0.5)
            let path = Path(roundedRect: cell.frame, cornerRadius: radius, style: .continuous)
            if cell.node.isDirectory {
                context.fill(path, with: .color(cell.color.opacity(0.4)))
                context.stroke(path, with: .color(.black.opacity(0.06)), lineWidth: 1)
            } else {
                context.fill(path, with: .color(cell.color.opacity(0.85)))
            }
        }

        // selection highlight
        if let selected = viewModel.selectedNode,
           let cell = cells.first(where: { $0.node === selected }) {
            let path = Path(roundedRect: cell.frame, cornerRadius: 4, style: .continuous)
            context.stroke(path, with: .color(theme.ink), lineWidth: 1.5)
        }

        // labels
        for cell in cells where cell.frame.width > 58 && cell.frame.height > 22 {
            let sizeUnits = Int((cell.frame.width - 12) / 6)
            guard sizeUnits >= 3 else { continue }
            let fontSize = min(9.5, Double(sizeUnits))
            let name = cell.node.name
            let shown = name.count <= sizeUnits ? name : String(name.prefix(max(1, sizeUnits - 1))) + "…"
            context.draw(
                Text(shown)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75)),
                at: CGPoint(x: cell.frame.minX + 6, y: cell.frame.minY + 8),
                anchor: .topLeading)
        }
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
