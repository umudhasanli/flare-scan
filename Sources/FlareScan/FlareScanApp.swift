import SwiftUI

@main
struct FlareScanApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Qovluq Seç və Tara…") {
                    app.chooseAndScan()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
