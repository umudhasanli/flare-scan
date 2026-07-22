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
        .alert("Zibil qutusuna köçürülsün?", isPresented: deletionConfirmation) {
            Button("Ləğv et", role: .cancel) { app.cancelDeletion() }
            Button("Zibil qutusuna köçür", role: .destructive) { app.confirmDeletion() }
        } message: {
            if let node = app.pendingDeletion {
                Text("\(node.isDirectory ? "Qovluq" : "Fayl"): \(node.url.path)\nÖlçü: \(ByteFormat.string(node.size))\n\nElement macOS Zibil qutusuna köçürüləcək və oradan bərpa edilə bilər.")
            }
        }
        .alert("Əməliyyat tamamlanmadı", isPresented: deletionErrorPresented) {
            Button("Oldu", role: .cancel) { app.deletionError = nil }
        } message: {
            Text(app.deletionError ?? "Naməlum xəta")
        }
        .alert("Hesabat saxlanmadı", isPresented: exportErrorPresented) {
            Button("Oldu", role: .cancel) { app.exportError = nil }
        } message: {
            Text(app.exportError ?? "Naməlum xəta")
        }
        .alert("Scan tarixçəsi yenilənmədi", isPresented: historyErrorPresented) {
            Button("Oldu", role: .cancel) { app.historyError = nil }
        } message: {
            Text(app.historyError ?? "Naməlum xəta")
        }
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(get: { app.pendingDeletion != nil },
                set: { if !$0 { app.cancelDeletion() } })
    }

    private var deletionErrorPresented: Binding<Bool> {
        Binding(get: { app.deletionError != nil },
                set: { if !$0 { app.deletionError = nil } })
    }

    private var exportErrorPresented: Binding<Bool> {
        Binding(get: { app.exportError != nil },
                set: { if !$0 { app.exportError = nil } })
    }

    private var historyErrorPresented: Binding<Bool> {
        Binding(get: { app.historyError != nil },
                set: { if !$0 { app.historyError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if app.isScanning {
            ScanningView()
        } else if let focus = app.focus {
            if app.mode == .insights {
                if let insights = app.insights {
                    InsightsView(insights: insights)
                } else {
                    ProgressView("Analitika hazırlanır…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    VisualizationContainer(focus: focus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    DetailPanel(focus: focus)
                        .frame(width: 300)
                }
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
            case .insights:
                EmptyView()
            }
        }
        .padding(12)
    }
}
