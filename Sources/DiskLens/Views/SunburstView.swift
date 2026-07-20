import SwiftUI

/// Interactive concentric-ring ("sunburst") view of the focus node.
/// Hover to inspect, click a ring to zoom in, click the center to go up.
struct SunburstView: View {
    let focus: FileNode
    let onHover: (FileNode?) -> Void
    let onDrill: (FileNode) -> Void
    let onUp: () -> Void

    private let maxDepth = 6

    @State private var segments: [SunburstSegment] = []
    @State private var canvasSize: CGSize = .zero
    @State private var hoveredID: UUID?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for segment in segments {
                    context.fill(segment.path, with: .color(segment.color))
                    if segment.node.id == hoveredID {
                        context.fill(segment.path, with: .color(.white.opacity(0.22)))
                    }
                    context.stroke(segment.path, with: .color(.black.opacity(0.14)), lineWidth: 1)
                }
                drawCenter(context: context, size: size)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let node = SunburstLayout.hitTest(point, in: segments)
                    hoveredID = node?.id
                    onHover(node)
                case .ended:
                    hoveredID = nil
                    onHover(nil)
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(value.location)
                }
            )
            .onAppear { recompute(size: geo.size) }
            .onChange(of: geo.size) { _, newSize in recompute(size: newSize) }
            .onChange(of: focus.id) { _, _ in recompute(size: geo.size) }
        }
    }

    private func recompute(size: CGSize) {
        canvasSize = size
        segments = SunburstLayout.compute(focus: focus, size: size, maxDepth: maxDepth)
    }

    private func handleTap(_ point: CGPoint) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()

        // Clicking the empty center goes up a level.
        if radius <= SunburstLayout.holeRadius(size: canvasSize, maxDepth: maxDepth) {
            onUp()
            return
        }
        if let node = SunburstLayout.hitTest(point, in: segments), node.isDirectory {
            onDrill(node)
        }
    }

    private func drawCenter(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.draw(
            Text(focus.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary),
            at: CGPoint(x: center.x, y: center.y - 9))
        context.draw(
            Text(ByteFormat.string(focus.size))
                .font(.system(size: 12))
                .foregroundStyle(.secondary),
            at: CGPoint(x: center.x, y: center.y + 9))
    }
}
