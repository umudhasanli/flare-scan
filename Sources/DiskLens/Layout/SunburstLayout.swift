import SwiftUI
import Foundation

/// One drawable arc (annular sector) in the sunburst.
struct SunburstSegment: Identifiable {
    let id = UUID()
    let node: FileNode
    let depth: Int
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: CGFloat   // radians, in the sweep space starting at `sweepStart`
    let endAngle: CGFloat
    let color: Color

    /// The filled annular-sector path for this segment.
    var path: Path {
        var p = Path()
        p.addArc(center: center, radius: outerRadius,
                 startAngle: .radians(Double(startAngle)),
                 endAngle: .radians(Double(endAngle)),
                 clockwise: false)
        p.addLine(to: CGPoint(x: center.x + innerRadius * cos(endAngle),
                              y: center.y + innerRadius * sin(endAngle)))
        p.addArc(center: center, radius: innerRadius,
                 startAngle: .radians(Double(endAngle)),
                 endAngle: .radians(Double(startAngle)),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Computes and hit-tests the concentric-ring layout for a focus node.
enum SunburstLayout {

    static let sweepStart: CGFloat = -.pi / 2      // start at the top
    static let fullSweep: CGFloat = 2 * .pi

    /// Radius of the empty center hole (equals one ring width).
    static func holeRadius(size: CGSize, maxDepth: Int) -> CGFloat {
        let maxRadius = min(size.width, size.height) / 2 - 8
        return max(1, maxRadius / CGFloat(maxDepth + 1))
    }

    static func compute(focus: FileNode, size: CGSize, maxDepth: Int) -> [SunburstSegment] {
        guard size.width > 20, size.height > 20 else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ring = holeRadius(size: size, maxDepth: maxDepth)
        var segments: [SunburstSegment] = []

        func recurse(_ node: FileNode, depth: Int, start: CGFloat, end: CGFloat, hue: Double) {
            if depth > maxDepth { return }

            if depth >= 1 {
                let inner = ring * CGFloat(depth)
                let outer = inner + ring
                segments.append(SunburstSegment(
                    node: node,
                    depth: depth,
                    center: center,
                    innerRadius: inner,
                    outerRadius: outer,
                    startAngle: start,
                    endAngle: end,
                    color: Palette.color(hue: hue, depth: depth)))
            }

            guard node.isDirectory, node.size > 0, !node.children.isEmpty, depth < maxDepth else {
                return
            }

            let span = end - start
            let total = Double(node.size)
            var angle = start
            for (index, child) in node.children.enumerated() {
                let fraction = Double(child.size) / total
                let childEnd = angle + span * CGFloat(fraction)
                // Skip slivers thinner than ~0.34° — invisible and expensive.
                if childEnd - angle >= 0.006 {
                    let childHue = depth == 0 ? Palette.hue(forIndex: index) : hue
                    recurse(child, depth: depth + 1, start: angle, end: childEnd, hue: childHue)
                }
                angle = childEnd
            }
        }

        recurse(focus, depth: 0, start: sweepStart, end: sweepStart + fullSweep, hue: 0)
        return segments
    }

    /// Returns the node whose arc contains `point`, if any.
    static func hitTest(_ point: CGPoint, in segments: [SunburstSegment]) -> FileNode? {
        guard let center = segments.first?.center else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()

        var theta = atan2(dy, dx)
        while theta < sweepStart { theta += 2 * .pi }
        while theta > sweepStart + fullSweep { theta -= 2 * .pi }

        for segment in segments
        where radius >= segment.innerRadius && radius <= segment.outerRadius
            && theta >= segment.startAngle && theta <= segment.endAngle {
            return segment.node
        }
        return nil
    }
}
