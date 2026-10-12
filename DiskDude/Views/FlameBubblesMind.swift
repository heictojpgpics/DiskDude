//
//  FlameBubblesMind.swift
//  DiskDude
//
//  FlameGraphView (Block: node/row/x/width/color — "Depth top to
//  bottom, size left to right"), BubblesView (Bubble: node/center/
//  radius/depth/isGroup/color — circle-packed via PackNode class),
//  MindMapView (Branch: node/point/parentPoint/angles/distances/depth/
//  dot/fill/accent/showsLabel — "Branches from the root, sized by
//  weight" via TreeItem class).
//

import SwiftUI

// MARK: - Flame graph

struct FlameGraphView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovered: FileNode?
    @State private var cache = LayoutCache<CanvasKey, [Block]>()

    struct Block: Identifiable, Hashable {
        let node: FileNode
        var row: Int
        var x: Double
        var width: Double
        var color: Color
        var id: ObjectIdentifier { node.id }
        static func == (l: Block, r: Block) -> Bool { l.node === r.node && l.x == r.x && l.width == r.width && l.row == r.row }
        func hash(into h: inout Hasher) { h.combine(node.id); h.combine(row) }
    }

    var body: some View {
        GeometryReader { geo in
            let key = CanvasKey(
                layout: VizKey(generation: viewModel.generation, node: folder.id,
                               width: Int(geo.size.width), height: Int(geo.size.height),
                               depth: Int(viewModel.depth), mode: viewModel.colorMode),
                width: Int(geo.size.width), height: Int(geo.size.height),
                selected: viewModel.selectedNode?.id,
                scheme: viewModel.colorSchemeActive,
                abbreviateLabels: viewModel.abbreviateLabels)
            let blocks = cache.compute(key: key) {
                layoutBlocks(width: geo.size.width)
            }
            let contentHeight = CGFloat(maxRow(blocks) + 1) * 60 + 2

            ScrollView(.vertical, showsIndicators: true) {
                Canvas { context, size in
                    for block in blocks {
                        drawBlock(block, in: &context)
                    }
                    if let hovered {
                        drawOverlay(hovered, blocks: blocks, in: &context)
                    }
                }
                .frame(width: geo.size.width, height: max(contentHeight, geo.size.height))
            }
        }
        .background(theme.background)
    }

    // MARK: - Canvas drawing (binary-exact: row 60, cell 58, radius 3, labels 13pt)

    private func cellRect(_ block: Block) -> CGRect {
        CGRect(x: block.x + 1, y: Double(block.row) * 60 + 1,
               width: max(block.width - 2, 0.6), height: 58)
    }

    private func drawBlock(_ block: Block, in context: inout GraphicsContext) {
        let rect = cellRect(block)
        let path = Path(roundedRect: rect, cornerRadius: min(rect.width * 0.5, 3), style: .continuous)
        context.fill(path, with: .color(block.color))
        if viewModel.selectedNode === block.node, block.row >= 1 {
            context.stroke(path, with: .color(block.color.opacity(0.8)), lineWidth: 1.5)
        }
        drawLabel(block, rect: rect, in: &context)
    }

    private func drawOverlay(_ node: FileNode, blocks: [Block], in context: inout GraphicsContext) {
        guard let block = blocks.first(where: { $0.node === node }) else { return }
        let rect = cellRect(block)
        let path = Path(roundedRect: rect, cornerRadius: min(rect.width * 0.5, 3), style: .continuous)
        context.fill(path, with: .color(.black.opacity(0.12)))
        context.stroke(path, with: .color(block.color.opacity(0.8)), lineWidth: 1.5)
    }

    private func drawLabel(_ block: Block, rect: CGRect, in context: inout GraphicsContext) {
        guard rect.width > 44 else { return }
        var label = block.node.name == "/" ? "/" : block.node.name
        let limit = Int((rect.width - 14) / 6.79)
        if limit > 2, limit < label.count {
            label = String(label.prefix(limit - 1)) + "…"
        }
        let text = Text(label)
            .font(.system(size: 13))
            .foregroundColor(theme.textPrimary)
        context.draw(text, at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
    }

    private func layoutBlocks(width: CGFloat) -> [Block] {
        var out: [Block] = []
        func walk(_ node: FileNode, row: Int, x: Double, w: Double) {
            guard row < Int(viewModel.depth), w > 0.8 else { return }
            out.append(Block(node: node, row: row, x: x, width: w, color: color(node)))
            let children = node.isDirectory ? Array(node.sortedChildren.prefix(80)) : []
            let total = children.reduce(0.0) { $0 + max(1, Double($1.sizeOnDisk)) }
            guard total > 0 else { return }
            var cx = x
            for child in children {
                let share = w * max(1, Double(child.sizeOnDisk)) / total
                walk(child, row: row + 1, x: cx, w: share)
                cx += share
            }
        }
        walk(folder, row: 0, x: 0, w: Double(width))
        return out
    }

    private func maxRow(_ blocks: [Block]) -> Int {
        blocks.map(\.row).max() ?? 0
    }

    private func color(_ node: FileNode) -> Color {
        switch viewModel.colorMode {
        case .type: return theme.categoryColor(node.category)
        case .folder: return theme.folderColor(depth: node.depth)
        case .age: return theme.ageColor(age: Date().timeIntervalSince1970 - node.modifiedStamp,
                                         maxAge: 365 * 24 * 3600 * 2)
        }
    }
}

// MARK: - Bubbles (circle packing)

struct BubblesView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovered: FileNode?
    @State private var cache = LayoutCache<CanvasKey, [Bubble]>()

    struct Bubble: Identifiable, Hashable {
        let node: FileNode
        var center: CGPoint
        var radius: Double
        var depth: Int
        var isGroup: Bool
        var color: Color
        var id: ObjectIdentifier { node.id }
        static func == (l: Bubble, r: Bubble) -> Bool { l.node === r.node && l.center == r.center && Int(l.radius * 100) == Int(r.radius * 100) }
        func hash(into h: inout Hasher) { h.combine(node.id) }
    }

    var body: some View {
        GeometryReader { geo in
            let key = CanvasKey(
                layout: VizKey(generation: viewModel.generation, node: folder.id,
                               width: Int(geo.size.width), height: Int(geo.size.height),
                               depth: Int(viewModel.depth), mode: viewModel.colorMode),
                width: Int(geo.size.width), height: Int(geo.size.height),
                selected: viewModel.selectedNode?.id,
                scheme: viewModel.colorSchemeActive,
                abbreviateLabels: viewModel.abbreviateLabels)
            let bubbles = cache.compute(key: key) {
                let root = PackNode(node: folder, depth: 0, color: color(folder))
                root.pack(width: Double(geo.size.width), height: Double(geo.size.height),
                          maxDepth: Int(viewModel.depth))
                return root.flatten().map { pack in
                    Bubble(node: pack.node,
                           center: CGPoint(x: pack.x, y: pack.y),
                           radius: pack.r,
                           depth: pack.depth,
                           isGroup: pack.depth < Int(viewModel.depth) && pack.node.isDirectory,
                           color: pack.color ?? color(pack.node))
                }
            }
            ZStack {
                // Canvas renderer (binary-exact: ellipseIn, 3 fill states, 1.2/1.0/1.6 strokes)
                Canvas { context, size in
                    for bubble in bubbles {
                        drawBubble(bubble, in: &context)
                    }
                }
            }
        }
        .background(theme.background)
    }

    private func drawBubble(_ bubble: Bubble, in context: inout GraphicsContext) {
        let rect = CGRect(x: bubble.center.x - bubble.radius,
                          y: bubble.center.y - bubble.radius,
                          width: bubble.radius * 2, height: bubble.radius * 2)
        let path = Path(ellipseIn: rect)
        let hoveredState = hovered === bubble.node
        let hasSelection = viewModel.selectedNode != nil
        let matchesSelection = viewModel.selectedNode === bubble.node

        if !hasSelection {
            // Normal: theme fill + 1.2 stroke (binary default state)
            context.fill(path, with: .color(bubble.color.opacity(bubble.isGroup ? 0.32 : 0.85)))
            context.stroke(path, with: .color(bubble.color.opacity(0.9)), lineWidth: bubble.isGroup ? 1.0 : 1.2)
        } else if matchesSelection || hoveredState {
            // Highlighted: 0.85 fill + white 0.35 stroke @ 0.8
            context.fill(path, with: .color(bubble.color.opacity(0.85)))
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
        } else {
            // Dimmed: 0.32 fill + 0.9 self-color stroke @ 1.0
            context.fill(path, with: .color(bubble.color.opacity(0.32)))
            context.stroke(path, with: .color(bubble.color.opacity(0.9)), lineWidth: 1.0)
        }
        // Selection ring: text color at 0.8 opacity, 1.6 wide
        if matchesSelection, bubble.depth >= 1 {
            context.stroke(path, with: .color(theme.textPrimary.opacity(0.8)), lineWidth: 1.6)
        }
        drawBubbleLabel(bubble, in: &context)
    }

    private func drawBubbleLabel(_ bubble: Bubble, in context: inout GraphicsContext) {
        guard bubble.radius > 34 else { return }
        // Large: 14pt semibold name + size line 14pt below (binary tier 1)
        if bubble.radius >= 45 {
            let name = Text(bubble.node.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            context.draw(name, at: CGPoint(x: bubble.center.x, y: bubble.center.y - 6), anchor: .center)
            let size = Text(formatBytes(bubble.node.sizeOnDisk))
                .font(.system(size: 10))
                .foregroundColor(theme.textSecondary)
            context.draw(size, at: CGPoint(x: bubble.center.x, y: bubble.center.y + 8), anchor: .center)
        } else {
            // Medium: adaptive size clamp(r/9, 9.5, 14), char budget (r*1.3)/(size*0.58)
            let fontSize = min(max(bubble.radius / 9, 9.5), 14)
            let limit = Int((bubble.radius * 1.3) / (fontSize * 0.58))
            guard limit >= 3 else { return }
            var label = bubble.node.name
            if limit < label.count {
                label = String(label.prefix(limit - 1)) + "…"
            }
            let text = Text(label)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            context.draw(text, at: bubble.center, anchor: .center)
        }
    }

    private func color(_ node: FileNode) -> Color {
        switch viewModel.colorMode {
        case .type: return theme.categoryColor(node.category)
        case .folder: return theme.folderColor(depth: node.depth)
        case .age: return theme.ageColor(age: Date().timeIntervalSince1970 - node.modifiedStamp,
                                         maxAge: 365 * 24 * 3600 * 2)
        }
    }
}

/// Circle-packing node (recovered class PackNode: node, depth, color,
/// r, x, y, children).
final class PackNode {
    let node: FileNode
    let depth: Int
    var color: Color?
    var r: Double = 0
    var x: Double = 0
    var y: Double = 0
    var children: [PackNode]

    init(node: FileNode, depth: Int, color: Color? = nil) {
        self.node = node
        self.depth = depth
        self.color = color
        self.children = []
    }

    /// Simple squarified-then-circular approximation: children are
    /// arranged in concentric rings around the parent.
    func pack(width: Double, height: Double, maxDepth: Int) {
        let bound = min(width, height) / 2 - 6
        let childNodes = node.isDirectory ? Array(node.sortedChildren.prefix(24)) : []
        let total = childNodes.reduce(0.0) { $0 + max(1, Double($1.sizeOnDisk)) }
        r = bound
        x = width / 2
        y = height / 2
        guard total > 0, !childNodes.isEmpty, depth < maxDepth else { return }

        // Area-proportional radii, placed on a spiral around center.
        var placed: [(Double, Double, Double)] = []  // x, y, r
        var angle = 0.0
        var ringR = 0.0
        for child in childNodes {
            let areaShare = max(1, Double(child.sizeOnDisk)) / total
            let cr = bound * 0.92 * sqrt(areaShare)
            let pack = PackNode(node: child, depth: depth + 1)
            // Walk outward until the circle fits.
            var tries = 0
            var px = x + cos(angle) * (ringR + cr)
            var py = y + sin(angle) * (ringR + cr)
            while tries < 40 && placed.contains(where: { dist($0.0, $0.1, px, py) < $0.2 + cr + 2 }) {
                angle += 0.55
                if angle > 2 * .pi { angle -= 2 * .pi; ringR += cr * 0.4 }
                px = x + cos(angle) * (ringR + cr)
                py = y + sin(angle) * (ringR + cr)
                tries += 1
            }
            placed.append((px, py, cr))
            pack.r = cr
            pack.x = px
            pack.y = py
            pack.color = nil
            pack.pack(width: width, height: height, maxDepth: maxDepth)
            children.append(pack)
        }
    }

    private func dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
    }

    func flatten() -> [PackNode] {
        [self] + children.flatMap(\.flatten)
    }
}

// MARK: - Mind map

struct MindMapView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovered: FileNode?
    @State private var cache = LayoutCache<CanvasKey, [Branch]>()

    struct Branch: Identifiable, Hashable {
        let node: FileNode
        var point: CGPoint
        var parentPoint: CGPoint
        var angle: Double
        var parentAngle: Double
        var distance: Double
        var parentDistance: Double
        var depth: Int
        var dot: Double
        var fill: Color
        var accent: Color
        var showsLabel: Bool
        var id: ObjectIdentifier { node.id }
        static func == (l: Branch, r: Branch) -> Bool { l.node === r.node }
        func hash(into h: inout Hasher) { h.combine(node.id) }
    }

    var body: some View {
        GeometryReader { geo in
            let key = CanvasKey(
                layout: VizKey(generation: viewModel.generation, node: folder.id,
                               width: Int(geo.size.width), height: Int(geo.size.height),
                               depth: Int(viewModel.depth), mode: viewModel.colorMode),
                width: Int(geo.size.width), height: Int(geo.size.height),
                selected: viewModel.selectedNode?.id,
                scheme: viewModel.colorSchemeActive,
                abbreviateLabels: viewModel.abbreviateLabels)
            let branches = cache.compute(key: key) {
                buildBranches(width: geo.size.width, height: geo.size.height)
            }
            ZStack {
                ForEach(branches) { branch in
                    branchView(branch)
                }
            }
            .clipped()
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func branchView(_ branch: Branch) -> some View {
        // Binary uses cubic bezier links: addCurve(to:control1:control2:)
        Path { p in
            p.move(to: branch.parentPoint)
            let c1 = CGPoint(x: (branch.parentPoint.x + branch.point.x) / 2,
                             y: branch.parentPoint.y)
            let c2 = CGPoint(x: (branch.parentPoint.x + branch.point.x) / 2,
                             y: branch.point.y)
            p.addCurve(to: branch.point, control1: c1, control2: c2)
        }
        .stroke(branch.fill.opacity(0.55), style: StrokeStyle(lineWidth: max(1.5, branch.dot * 0.6), lineCap: .round))

        Circle()
            .fill(branch.fill)
            .frame(width: branch.dot, height: branch.dot)
            .position(branch.point)
            .overlay {
                if branch.showsLabel && branch.dot > 16 {
                    Text(branch.node.name)
                        .font(.system(size: mindMapFontSize(dot: branch.dot), weight: .semibold))
                        .foregroundStyle(.black.opacity(0.6))
                        .position(x: branch.point.x, y: branch.point.y + branch.dot / 2 + 9)
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture {
                if branch.node.isDirectory { viewModel.enter(folder: branch.node) }
                else { viewModel.select(branch.node) }
            }
            .onHover { over in hovered = over ? branch.node : nil }
            .overlay(alignment: .topLeading) {
                if hovered === branch.node {
                    HoverChip(node: branch.node).offset(x: 14, y: 8).allowsHitTesting(false).zIndex(2)
                }
            }
    }

    /// Binary label grid: 12.0 / 11.5 / 11.0 / 9.0 by node weight.
    private func mindMapFontSize(dot: CGFloat) -> CGFloat {
        switch dot {
        case 44...: return 12
        case 30..<44: return 11.5
        case 20..<30: return 11
        default: return 9
        }
    }

    /// Tree layout: root at center-left; children fan out by weight.
    private func buildBranches(width: CGFloat, height: CGFloat) -> [Branch] {
        var out: [Branch] = []
        let rootPoint = CGPoint(x: 70, y: height / 2)
        let maxDepth = Int(viewModel.depth)
        let total = folder.children.reduce(0.0) { $0 + max(1, Double($1.sizeOnDisk)) }
        var y = height / 2
        let item = TreeItem(node: folder)

        func walk(_ item: TreeItem, parentPoint: CGPoint, parentAngle: Double, depth: Int) {
            guard depth < maxDepth + 1 else { return }
            let children = Array(item.node.sortedChildren.prefix(30))
            let span = height * 0.9 / max(1, Double(1 + item.leaves))
            var cursor = y - span * Double(item.leaves) / 2
            for child in children {
                let leafShare = Double(max(1, item.leafCount(of: child))) / max(1, Double(max(1, item.leaves)))
                let cy = cursor + span * leafShare / 2
                let cx = parentPoint.x + (width - 110) / Double(maxDepth) * 0.85
                let dot = max(4, min(34, 34 * sqrt(max(1, Double(child.sizeOnDisk)) / max(1, total))))
                let branch = Branch(node: child,
                                    point: CGPoint(x: min(cx, width - 30), y: cy),
                                    parentPoint: parentPoint,
                                    angle: .pi,
                                    parentAngle: parentAngle,
                                    distance: Double(depth),
                                    parentDistance: Double(depth - 1),
                                    depth: depth,
                                    dot: dot,
                                    fill: color(child),
                                    accent: theme.ink,
                                    showsLabel: dot > 12)
                out.append(branch)
                let childItem = TreeItem(node: child)
                walk(childItem, parentPoint: branch.point, parentAngle: 0, depth: depth + 1)
                cursor += span * leafShare
            }
        }

        walk(item, parentPoint: rootPoint, parentAngle: 0, depth: 1)
        return out
    }

    private func color(_ node: FileNode) -> Color {
        switch viewModel.colorMode {
        case .type: return theme.categoryColor(node.category)
        case .folder: return theme.folderColor(depth: node.depth)
        case .age: return theme.ageColor(age: Date().timeIntervalSince1970 - node.modifiedStamp,
                                         maxAge: 365 * 24 * 3600 * 2)
        }
    }
}

/// Outline/mind-map helper (recovered class TreeItem: node, children, leaves).
final class TreeItem {
    let node: FileNode
    var children: [TreeItem]
    var leaves: Int

    init(node: FileNode) {
        self.node = node
        let kids = node.isDirectory ? Array(node.sortedChildren.prefix(24)) : []
        self.children = kids.map(TreeItem.init)
        self.leaves = children.isEmpty ? 1 : children.reduce(0) { $0 + $1.leaves }
    }

    func leafCount(of child: FileNode) -> Int {
        let kid = child.isDirectory ? Array(child.sortedChildren.prefix(24)) : []
        return kid.isEmpty ? 1 : kid.reduce(0) { acc, _ in acc + 1 }
    }
}
