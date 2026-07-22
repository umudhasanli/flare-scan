import SwiftUI

/// Interactive nested treemap of the focus node. Hover to inspect, click a
/// directory rectangle to zoom in.
struct TreemapView: View {
    let focus: FileNode
    let onHover: (FileNode?) -> Void
    let onDrill: (FileNode) -> Void

    private let maxDepth = 4

    @State private var rects: [TreemapRect] = []
    @State private var hoveredID: UUID?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                for rect in rects {
                    let path = Path(rect.rect)
                    context.fill(path, with: .color(rect.color))
                    context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 1)

                    if rect.node.id == hoveredID {
                        context.fill(path, with: .color(.white.opacity(0.22)))
                        context.stroke(path, with: .color(.primary.opacity(0.65)), lineWidth: 2)
                    }
                    if rect.rect.width > 46, rect.rect.height > 18 {
                        drawLabel(context: context, rect: rect)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let node = TreemapLayout.hitTest(point, in: rects)
                    hoveredID = node?.id
                    onHover(node)
                case .ended:
                    hoveredID = nil
                    onHover(nil)
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let node = TreemapLayout.hitTest(value.location, in: rects), node.isDirectory {
                        onDrill(node)
                    }
                }
            )
            .onAppear { recompute(size: geo.size) }
            .onChange(of: geo.size) { _, newSize in recompute(size: newSize) }
            .onChange(of: focus.id) { _, _ in recompute(size: geo.size) }
        }
    }

    private func recompute(size: CGSize) {
        rects = TreemapLayout.compute(focus: focus, size: size, maxDepth: maxDepth)
    }

    private func drawLabel(context: GraphicsContext, rect: TreemapRect) {
        context.draw(
            Text(rect.node.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.black.opacity(0.75)),
            at: CGPoint(x: rect.rect.minX + 5, y: rect.rect.minY + 10),
            anchor: .leading)
    }
}
