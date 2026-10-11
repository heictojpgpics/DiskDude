//
//  SunburstView.swift
//  DiskDude
//
//  Reconstructed: radial rings (SunArc: node, ring, start, end, color),
//  angle = share of parent, tap to focus, hover chip.
//

import SwiftUI

struct SunburstView: View {
    let folder: FileNode
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme
    @State private var hovered: FileNode?
    @State private var cache = LayoutCache<CanvasKey, [SunArc]>()

    struct SunArc: Identifiable, Hashable {
        let node: FileNode
        var ring: Int
        var start: Double
        var end: Double
        var color: Color
        var id: ObjectIdentifier { node.id }
        static func == (l: SunArc, r: SunArc) -> Bool { l.node === r.node && l.start == r.start && l.end == r.end && l.ring == r.ring }
        func hash(into h: inout Hasher) { h.combine(node.id); h.combine(ring); h.combine(start) }
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outer = min(geo.size.width, geo.size.height) / 2 - 8
            let ringWidth = outer / max(2, Double(viewModel.depth))

            let key = canvasKey(geo)
            let arcs = cache.compute(key: key) {
                buildArcs(parent: folder, ring: 0, start: 0, end: 2 * .pi, arcs: [])
            }

            ZStack {
                ForEach(arcs) { arc in
                    arcShape(arc, center: center, ringWidth: ringWidth)
                }
                // Center label
                Text(folder.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .position(center)
            }
            .clipped()
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func arcShape(_ arc: SunArc, center: CGPoint, ringWidth: CGFloat) -> some View {
        let inner = ringWidth * CGFloat(arc.ring + 0.12)
        let outer = ringWidth * CGFloat(arc.ring + 0.88)
        Path { p in
            p.addArc(center: center, radius: outer,
                     startAngle: .radians(arc.start), endAngle: .radians(arc.end), clockwise: false)
            p.addArc(center: center, radius: inner,
                     startAngle: .radians(arc.end), endAngle: .radians(arc.start), clockwise: true)
            p.closeSubpath()
        }
        .fill(arc.color.opacity(viewModel.selectedNode === arc.node ? 1.0 : 0.85))
        .onTapGesture {
            if arc.node.isDirectory {
                viewModel.enter(folder: arc.node)
            } else {
                viewModel.select(arc.node)
            }
        }
        .onHover { over in hovered = over ? arc.node : nil }
        .overlay(alignment: .topLeading) {
            if hovered === arc.node {
                HoverChip(node: arc.node).offset(x: 16, y: 10).allowsHitTesting(false)
            }
        }
    }

    private func buildArcs(parent: FileNode, ring: Int, start: Double, end: Double, arcs: [SunArc]) -> [SunArc] {
        var out = arcs
        guard ring < Int(viewModel.depth), end > start else { return out }
        let children = Array(parent.sortedChildren.prefix(60))
        let total = children.reduce(0.0) { $0 + max(1.0, Double($1.sizeOnDisk)) }
        guard total > 0 else { return out }
        var angle = start
        let span = end - start
        for child in children {
            let share = max(1.0, Double(child.sizeOnDisk)) / total
            let childSpan = span * share
            out.append(SunArc(node: child, ring: ring,
                              start: angle, end: angle + childSpan,
                              color: color(for: child, depth: ring)))
            if child.isDirectory, childSpan > 0.02 {
                out = buildArcs(parent: child, ring: ring + 1,
                                start: angle + 0.004, end: angle + childSpan - 0.004, arcs: out)
            }
            angle += childSpan
        }
        return out
    }

    private func canvasKey(_ geo: GeometryProxy) -> CanvasKey {
        CanvasKey(
            layout: VizKey(generation: viewModel.generation, node: folder.id,
                           width: Int(geo.size.width), height: Int(geo.size.height),
                           depth: Int(viewModel.depth), mode: viewModel.colorMode),
            width: Int(geo.size.width), height: Int(geo.size.height),
            selected: viewModel.selectedNode?.id,
            scheme: viewModel.colorSchemeActive,
            abbreviateLabels: viewModel.abbreviateLabels)
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
