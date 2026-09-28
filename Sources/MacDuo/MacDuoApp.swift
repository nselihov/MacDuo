import SwiftUI

@main
struct MacDuoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacDuo", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(width: 520, height: 500)
                .task {
                    model.prepareOverlay()
                }
        }
        .defaultSize(width: 520, height: 500)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        WindowGroup("Диагностика MacDuo", id: "diagnostics") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("MacDuo", systemImage: "rectangle.split.2x1") {
            MacDuoStatusMenu(model: model)
        }
    }
}
