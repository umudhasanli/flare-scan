import SwiftUI

/// Right-hand panel: the focus node's largest children as a ranked, clickable
/// list with proportional bars.
struct DetailPanel: View {
    @EnvironmentObject var app: AppState
    let focus: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(focus.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteFormat.string(focus.size))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            if focus.children.isEmpty {
                Spacer()
                Text("Bu qovluq boşdur")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(focus.children.prefix(300))) { child in
                            DetailRow(node: child, isHovered: app.hovered?.id == child.id)
                                .contentShape(Rectangle())
                                .onTapGesture { app.drill(into: child) }
                                .onHover { inside in app.hovered = inside ? child : nil }
                        }
                    }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let node: FileNode
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(ByteFormat.string(node.size))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(2, geo.size.width * node.fractionOfParent), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
    }
}
