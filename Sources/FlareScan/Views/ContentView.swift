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
        .alert("Move to Trash?", isPresented: deletionConfirmation) {
            Button("Cancel", role: .cancel) { app.cancelDeletion() }
            Button("Move to Trash", role: .destructive) { app.confirmDeletion() }
        } message: {
            if let node = app.pendingDeletion {
                Text("\(node.isDirectory ? "Folder" : "File"): \(node.url.path)\nSize: \(ByteFormat.string(node.size))\n\nThe item will be moved to macOS Trash and can normally be restored from there.")
            }
        }
        .alert("The Operation Failed", isPresented: deletionErrorPresented) {
            Button("OK", role: .cancel) { app.deletionError = nil }
        } message: {
            Text(app.deletionError ?? "Unknown error")
        }
        .alert("Report Not Saved", isPresented: exportErrorPresented) {
            Button("OK", role: .cancel) { app.exportError = nil }
        } message: {
            Text(app.exportError ?? "Unknown error")
        }
        .alert("Scan History Not Updated", isPresented: historyErrorPresented) {
            Button("OK", role: .cancel) { app.historyError = nil }
        } message: {
            Text(app.historyError ?? "Unknown error")
        }
        .alert("Quit This App?", isPresented: appQuitConfirmation) {
            Button("Cancel", role: .cancel) { app.cancelAppQuit() }
            Button("Normal Quit", role: .destructive) { app.confirmAppQuit() }
        } message: {
            if let stat = app.pendingAppQuit {
                Text("\(stat.name) is currently using \(ByteFormat.string(stat.currentBytes)) of resident memory.\n\nFlare Scan will only send a normal quit request. The app may ask you to confirm unsaved work.")
            }
        }
        .alert("App Did Not Quit", isPresented: memoryQuitErrorPresented) {
            Button("OK", role: .cancel) { app.memoryQuitError = nil }
        } message: {
            Text(app.memoryQuitError ?? "Unknown error")
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

    private var appQuitConfirmation: Binding<Bool> {
        Binding(get: { app.pendingAppQuit != nil },
                set: { if !$0 { app.cancelAppQuit() } })
    }

    private var memoryQuitErrorPresented: Binding<Bool> {
        Binding(get: { app.memoryQuitError != nil },
                set: { if !$0 { app.memoryQuitError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if app.mode == .memory {
            MemoryWatchView()
        } else if app.isScanning {
            ScanningView()
        } else if let focus = app.focus {
            if app.mode == .insights {
                if let insights = app.insights {
                    InsightsView(insights: insights)
                } else {
                    ProgressView("Preparing insights…")
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
            case .memory:
                EmptyView()
            }
        }
        .padding(12)
    }
}
