import SwiftUI

@main
struct FlareScanApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder and Scan…") {
                    app.chooseAndScan()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra {
            MemoryMenuBarView()
                .environmentObject(app)
        } label: {
            Label("Flare Scan", systemImage: "memorychip")
        }
        .menuBarExtraStyle(.window)
    }
}
