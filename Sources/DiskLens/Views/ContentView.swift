import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            content
            Divider()
            StatusBar()
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.isScanning {
            ScanningView()
        } else if let focus = app.focus {
            HStack(spacing: 0) {
                VisualizationContainer(focus: focus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                DetailPanel(focus: focus)
                    .frame(width: 300)
            }
        } else {
            EmptyStateView()
        }
    }
}

/// Switches between the two visualizations and wires their hover/drill callbacks
/// back into `AppState`.
private struct VisualizationContainer: View {
    @EnvironmentObject var app: AppState
    let focus: FileNode

    var body: some View {
        Group {
            switch app.mode {
            case .sunburst:
                SunburstView(focus: focus,
                             onHover: { app.hovered = $0 },
                             onDrill: { app.drill(into: $0) },
                             onUp: { app.goUp() })
            case .treemap:
                TreemapView(focus: focus,
                            onHover: { app.hovered = $0 },
                            onDrill: { app.drill(into: $0) })
            }
        }
        .padding(12)
    }
}
