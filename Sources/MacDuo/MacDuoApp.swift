import AppKit
import SwiftUI

enum MacDuoIcon {
    static let image: NSImage = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApplication.shared.applicationIconImage
        }
        return image
    }()
}

@main
struct MacDuoApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.applicationIconImage = MacDuoIcon.image
    }

    var body: some Scene {
        WindowGroup("MacDuo", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(width: 520, height: 460)
                .task {
                    model.prepareOverlay()
                }
        }
        .defaultSize(width: 520, height: 460)
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
