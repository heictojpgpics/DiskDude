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
            let rowHeight = max(13.0, (geo.size.height - 8) / max(1, CGFloat(maxRow(blocks) + 1)))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(blocks) { block in
                        blockView(block, rowHeight: rowHeight)
                    }
                }
                .padding(4)
                .frame(width: geo.size.width, alignment: .leading)
            }
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func blockView(_ block: Block, rowHeight: CGFloat) -> some View {
        let selected = viewModel.selectedNode === block.node
        HStack(spacing: 4) {
            if block.width > 70 {
                Text(block.node.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(width: max(1.5, block.width), height: rowHeight - 2)
        .background(RoundedRectangle(cornerRadius: 2).fill(block.color.opacity(selected ? 1 : 0.85)))
        .padding(.leading, block.x)
        .onTapGesture {
            if block.node.isDirectory { viewModel.enter(folder: block.node) }
            else { viewModel.select(block.node) }
        }
        .onHover { over in hovered = over ? block.node : nil }
        .overlay(alignment: .topLeading) {
            if hovered === block.node {
                HoverChip(node: block.node).offset(y: 14).allowsHitTesting(false).zIndex(3)
            }
        }
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
                ForEach(bubbles) { bubble in
                    bubbleView(bubble)
                }
            }
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func bubbleView(_ bubble: Bubble) -> some View {
        let selected = viewModel.selectedNode === bubble.node
        ZStack {
            Circle()
                .fill(bubble.color.opacity(bubble.isGroup ? 0.22 : 0.75))
                .overlay(Circle().strokeBorder(selected ? theme.text : bubble.color.opacity(0.9),
                                                lineWidth: selected ? 2 : 1))
            if bubble.radius > 34 {
                VStack(spacing: 2) {
                    Text(bubble.node.name)
                        .font(.system(size: min(11, bubble.radius / 4.2), weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(bubble.node.sizeOnDisk, format: .byteCount(style: .file))
                        .font(.system(size: min(9, bubble.radius / 5.5)))
                        .opacity(0.8)
                }
                .foregroundStyle(bubble.isGroup ? theme.text : .black.opacity(0.7))
            }
        }
        .frame(width: bubble.radius * 2, height: bubble.radius * 2)
        .position(bubble.center)
        .onTapGesture {
            if bubble.node.isDirectory { viewModel.enter(folder: bubble.node) }
            else { viewModel.select(bubble.node) }
        }
        .onHover { over in hovered = over ? bubble.node : nil }
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
        Path { p in
            p.move(to: branch.parentPoint)
            let mid = CGPoint(x: (branch.parentPoint.x + branch.point.x) / 2,
                              y: branch.parentPoint.y)
            p.addQuadCurve(to: branch.point, control: mid)
        }
        .stroke(branch.fill.opacity(0.55), style: StrokeStyle(lineWidth: max(1.5, branch.dot * 0.6), lineCap: .round))

        Circle()
            .fill(branch.fill)
            .frame(width: branch.dot, height: branch.dot)
            .position(branch.point)
            .overlay {
                if branch.showsLabel && branch.dot > 16 {
                    Text(branch.node.name)
                        .font(.system(size: min(10, branch.dot / 3.2), weight: .semibold))
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
