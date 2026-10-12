//
//  SunburstView.swift
//  DiskDude
//
//  Reconstructed: Canvas renderer (binary-exact constants).
//  Geometry: half = min(w,h)/2 - 18; centerRadius = half < 140 ? 28 :
//  min(half*0.2, 80); ringWidth = (max(half,140) - centerRadius) / depth.
//  Base angle -pi/2 (12 o'clock). Labels 9pt .medium, 0.85 opacity,
//  char budget (ringWidth-10)/5.5, arc >= 13pt, radial/tangential + flip.
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
            let half = min(geo.size.width, geo.size.height) / 2 - 18
            let centerRadius: CGFloat = half < 140 ? 28 : min(half * 0.2, 80)
            let ringWidth = (max(half, 140) - centerRadius) / CGFloat(max(2, viewModel.depth))

            let key = canvasKey(geo)
            let arcs = cache.compute(key: key) {
                buildArcs(parent: folder, ring: 0, start: 0, end: 2 * .pi, arcs: [])
            }

            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let base = -Double.pi / 2
                    for arc in arcs {
                        drawSegment(arc, in: &context, center: center,
                                    ringWidth: ringWidth, innerRadius: centerRadius, base: base)
                    }
                    drawLabels(arcs, in: &context, center: center,
                               ringWidth: ringWidth, innerRadius: centerRadius, base: base)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    tap(at: location, center: center, ringWidth: ringWidth,
                        innerRadius: centerRadius, arcs: arcs)
                }
                .onHover { over in
                    if over {
                        // hit-test is approximated by the tap geometry on demand
                    } else {
                        hovered = nil
                    }
                }
                // Center label: name in the inner disk
                Text(folder.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: max(centerRadius * 1.6, 44), height: 30)
                    .multilineTextAlignment(.center)
                    .position(center)
                if let hovered {
                    HoverChip(node: hovered)
                        .allowsHitTesting(false)
                        .offset(x: 16, y: 10)
                }
            }
            .clipped()
        }
        .background(theme.background)
    }

    // MARK: - Segment drawing (binary: addArc outer ccw + addArc inner cw + close)

    private func drawSegment(_ arc: SunArc, in context: inout GraphicsContext,
                             center: CGPoint, ringWidth: CGFloat, innerRadius: CGFloat, base: Double) {
        let inner = innerRadius + CGFloat(arc.ring) * ringWidth
        var path = Path()
        path.addArc(center: center, radius: inner + ringWidth,
                    startAngle: .radians(base + arc.start), endAngle: .radians(base + arc.end),
                    clockwise: false)
        path.addArc(center: center, radius: inner,
                    startAngle: .radians(base + arc.end), endAngle: .radians(base + arc.start),
                    clockwise: true)
        path.closeSubpath()
        context.fill(path, with: .color(arc.color))
        context.stroke(path, with: .color(arc.color.opacity(0.85)), lineWidth: 1.5)
        if arc.node === viewModel.selectedNode {
            context.stroke(path, with: .color(theme.ink), lineWidth: 1.5)
        }
    }

    // MARK: - Labels (binary: 9pt medium, 0.85 opacity, radial + tangential modes)

    private func drawLabels(_ arcs: [SunArc], in context: inout GraphicsContext,
                            center: CGPoint, ringWidth: CGFloat, innerRadius: CGFloat, base: Double) {
        guard ringWidth >= 40 else { return }
        let charBudget = Int((ringWidth - 10) / 5.5)
        for arc in arcs {
            let midR = innerRadius + (CGFloat(arc.ring) + 0.5) * ringWidth
            let arcWidth = (arc.end - arc.start) * midR
            guard arcWidth >= 13 else { continue }
            let mid = (arc.start + arc.end) / 2 + base
            let x = midR * CGFloat(cos(mid)) + center.x
            let y = midR * CGFloat(sin(mid)) + center.y
            let name = arc.node.name
            let label: String
            if Double(name.count) * 5.5 <= Double(ringWidth - 10) {
                label = name
            } else if Double(name.count) * 5.5 + 12 <= arcWidth, ringWidth >= 16 {
                // Fits tangentially — keep full name, rotate along the arc
                label = name
                draw(label, node: arc.node, at: (x, y), angle: mid + .pi / 2,
                     in: &context)
                continue
            } else {
                guard charBudget > 2, charBudget < name.count else { continue }
                label = String(name.prefix(charBudget - 1)) + "…"
            }
            // Radial orientation, flipped on the left half for readability
            var angle = mid + .pi / 2
            if cos(mid) < 0 { angle += .pi }
            draw(label, node: arc.node, at: (x, y), angle: angle, in: &context)
        }
    }

    private func draw(_ label: String, node: FileNode, at point: (CGFloat, CGFloat),
                      angle: Double, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: point.0, y: point.1)
        ctx.rotate(by: .radians(angle))
        let text = Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(labelColor(node: node).opacity(0.85))
        ctx.draw(text, at: .zero, anchor: .center)
    }

    private func labelColor(node: FileNode) -> Color {
        node === viewModel.selectedNode ? theme.ink : theme.textPrimary
    }

    // MARK: - Hit testing

    private func tap(at point: CGPoint, center: CGPoint, ringWidth: CGFloat,
                     innerRadius: CGFloat, arcs: [SunArc]) {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        let r = (dx * dx + dy * dy).squareRoot()
        var a = atan2(dy, dx) + Double.pi / 2
        if a < 0 { a += 2 * .pi }
        for arc in arcs {
            let inner = innerRadius + CGFloat(arc.ring) * ringWidth
            if r >= Double(inner) && r < Double(inner + ringWidth) &&
                a >= arc.start && a < arc.end {
                if arc.node.isDirectory { viewModel.enter(folder: arc.node) }
                else { viewModel.select(arc.node) }
                return
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
