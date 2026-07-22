import SwiftUI
import Foundation

/// One drawable rectangle in the treemap.
struct TreemapRect: Identifiable {
    let id = UUID()
    let node: FileNode
    let rect: CGRect
    let color: Color
    let depth: Int
}

/// Computes a nested, squarified treemap for a focus node. Squarifying keeps
/// rectangles close to squares, which makes relative sizes far easier to read
/// than naive slice-and-dice strips.
enum TreemapLayout {

    static func compute(focus: FileNode, size: CGSize, maxDepth: Int) -> [TreemapRect] {
        guard size.width > 8, size.height > 8 else { return [] }
        var output: [TreemapRect] = []

        func recurse(_ node: FileNode, rect: CGRect, depth: Int, hue: Double) {
            guard depth < maxDepth else { return }
            let children = node.children.filter { $0.size > 0 }
            guard !children.isEmpty else { return }

            let items = children.map { (node: $0, area: Double($0.size)) }
            let placed = squarify(items: items, rect: rect)

            for (index, placement) in placed.enumerated() {
                let child = placement.node
                let childRect = placement.rect
                let childHue = depth == 0 ? Palette.hue(forIndex: index) : hue
                output.append(TreemapRect(
                    node: child,
                    rect: childRect,
                    color: Palette.color(hue: childHue, depth: depth + 1),
                    depth: depth + 1))

                // Nest one level deeper inside sufficiently large directories,
                // leaving a small top margin so the parent stays visible.
                if child.isDirectory, childRect.width > 14, childRect.height > 14 {
                    let inset = childRect.insetBy(dx: 2, dy: 2)
                    let inner = CGRect(x: inset.minX,
                                       y: inset.minY + 3,
                                       width: inset.width,
                                       height: max(0, inset.height - 3))
                    if inner.width > 10, inner.height > 10 {
                        recurse(child, rect: inner, depth: depth + 1, hue: childHue)
                    }
                }
            }
        }

        recurse(focus, rect: CGRect(origin: .zero, size: size), depth: 0, hue: 0)
        return output
    }

    /// Returns the deepest node whose rectangle contains `point`.
    static func hitTest(_ point: CGPoint, in rects: [TreemapRect]) -> FileNode? {
        for rect in rects.reversed() where rect.rect.contains(point) {
            return rect.node
        }
        return nil
    }

    // MARK: - Squarified treemap

    private static func squarify(items: [(node: FileNode, area: Double)],
                                 rect: CGRect) -> [(node: FileNode, rect: CGRect)] {
        var result: [(node: FileNode, rect: CGRect)] = []
        let total = items.reduce(0) { $0 + $1.area }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        // Convert size units into pixel-area units.
        let scale = Double(rect.width) * Double(rect.height) / total
        let scaled = items.map { (node: $0.node, area: max($0.area * scale, 0.0000001)) }

        var free = rect
        var index = 0
        while index < scaled.count {
            let horizontal = free.width <= free.height
            let side = Double(horizontal ? free.width : free.height)
            guard side > 0 else { break }

            // Grow the current row while the worst aspect ratio keeps improving.
            var count = 1
            var bestWorst = worstAspect(rowAreas(scaled, index, count), side: side)
            while index + count < scaled.count {
                let worst = worstAspect(rowAreas(scaled, index, count + 1), side: side)
                if worst <= bestWorst {
                    bestWorst = worst
                    count += 1
                } else {
                    break
                }
            }

            let row = Array(scaled[index ..< index + count])
            let rowArea = row.reduce(0) { $0 + $1.area }
            let thickness = CGFloat(rowArea / side)

            if horizontal {
                var x = free.minX
                for item in row {
                    let width = CGFloat(item.area) / thickness
                    result.append((item.node, CGRect(x: x, y: free.minY, width: width, height: thickness)))
                    x += width
                }
                free = CGRect(x: free.minX, y: free.minY + thickness,
                              width: free.width, height: free.height - thickness)
            } else {
                var y = free.minY
                for item in row {
                    let height = CGFloat(item.area) / thickness
                    result.append((item.node, CGRect(x: free.minX, y: y, width: thickness, height: height)))
                    y += height
                }
                free = CGRect(x: free.minX + thickness, y: free.minY,
                              width: free.width - thickness, height: free.height)
            }
            index += count
        }
        return result
    }

    private static func rowAreas(_ scaled: [(node: FileNode, area: Double)],
                                 _ start: Int, _ count: Int) -> [Double] {
        (start ..< start + count).map { scaled[$0].area }
    }

    private static func worstAspect(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0 else { return .greatestFiniteMagnitude }
        let thickness = sum / side
        guard thickness > 0 else { return .greatestFiniteMagnitude }
        var worst = 1.0
        for area in areas where area > 0 {
            let length = area / thickness
            worst = max(worst, max(length / thickness, thickness / length))
        }
        return worst
    }
}
