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

private enum MacDuoMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()

            let back = NSBezierPath()
            back.lineWidth = 1.35
            back.lineCapStyle = .round
            back.lineJoinStyle = .round
            back.move(to: NSPoint(x: 8.7, y: 15.4))
            back.line(to: NSPoint(x: 5.5, y: 16.2))
            back.curve(to: NSPoint(x: 3.3, y: 14.3),
                       controlPoint1: NSPoint(x: 4.3, y: 16.8),
                       controlPoint2: NSPoint(x: 3.3, y: 15.7))
            back.line(to: NSPoint(x: 3.3, y: 5.7))
            back.curve(to: NSPoint(x: 5.7, y: 3.8),
                       controlPoint1: NSPoint(x: 3.3, y: 4.2),
                       controlPoint2: NSPoint(x: 4.5, y: 3.3))
            back.line(to: NSPoint(x: 8.7, y: 4.7))
            back.stroke()

            let front = NSBezierPath()
            front.lineWidth = 1.35
            front.lineCapStyle = .round
            front.lineJoinStyle = .round
            front.move(to: NSPoint(x: 8.7, y: 15.4))
            front.curve(to: NSPoint(x: 10.0, y: 17.0),
                        controlPoint1: NSPoint(x: 8.8, y: 16.1),
                        controlPoint2: NSPoint(x: 9.3, y: 16.7))
            front.line(to: NSPoint(x: 14.2, y: 18.5))
            front.curve(to: NSPoint(x: 16.8, y: 16.6),
                        controlPoint1: NSPoint(x: 15.5, y: 19.0),
                        controlPoint2: NSPoint(x: 16.8, y: 18.1))
            front.line(to: NSPoint(x: 16.8, y: 3.3))
            front.curve(to: NSPoint(x: 14.2, y: 1.5),
                        controlPoint1: NSPoint(x: 16.8, y: 1.8),
                        controlPoint2: NSPoint(x: 15.5, y: 1.0))
            front.line(to: NSPoint(x: 10.0, y: 3.1))
            front.curve(to: NSPoint(x: 8.7, y: 4.8),
                        controlPoint1: NSPoint(x: 9.2, y: 3.4),
                        controlPoint2: NSPoint(x: 8.7, y: 4.0))
            front.close()
            front.stroke()
            return true
        }
        image.isTemplate = true
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

        MenuBarExtra {
            MacDuoStatusMenu(model: model)
        } label: {
            Image(nsImage: MacDuoMenuBarIcon.image)
                .renderingMode(.template)
                .accessibilityLabel("MacDuo")
        }
    }
}
