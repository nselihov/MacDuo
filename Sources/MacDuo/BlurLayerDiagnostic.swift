import AppKit
import MacDuoCore
import MacDuoSkyLight
import ScreenCaptureKit

/// Captures one owned checkerboard and each render layer separately. The
/// diagnostic runs only when explicitly requested from the command line.
@MainActor
enum BlurLayerDiagnostic {
    private struct Failure: Error { let message: String }

    static func run() async throws {
        guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
            throw Failure(message: "Unlock the desktop before running the layer diagnostic")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw Failure(message: "Screen Recording permission is needed for the owned fixture")
        }
        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = number.uint32Value
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }), let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw Failure(message: "No active built-in display")
        }

        let fixtureBridge = try SkyLightBridge()
        let fixture = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.ignoresMouseEvents = true
        fixture.hasShadow = false
        fixture.level = .init(rawValue: Int(Int32.max - 3))
        fixture.contentView = BlurLayerFixture(frame: NSRect(origin: .zero, size: screen.frame.size))
        try fixtureBridge.present(fixture)
        let bridge = try SkyLightBridge()
        let surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: .desktop)
        defer { surface.close(); bridge.close(); fixture.close(); fixtureBridge.close() }

        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("blur-layer-diagnostic")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for angle in [80, 60, 40] {
            try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: Double(angle), velocity: 0),
                             tuning: .standard, immediate: true)
            for mode in FoldOverlaySurface.DiagnosticMode.allCases {
                surface.setDiagnosticMode(mode)
                try await Task.sleep(nanoseconds: 250_000_000)
                guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
                    throw Failure(message: "Desktop locked during the diagnostic")
                }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw Failure(message: "Built-in display unavailable")
                }
                let ids = [CGWindowID(fixture.windowNumber), CGWindowID(surface.window.windowNumber)]
                let windows = content.windows.filter {
                    ids.contains($0.windowID) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                }
                guard windows.count == ids.count else {
                    throw Failure(message: "Owned diagnostic windows unavailable")
                }
                let config = SCStreamConfiguration()
                config.width = 1200
                config.height = Int(1200 * screen.frame.height / screen.frame.width)
                config.showsCursor = false
                config.ignoreShadowsDisplay = true
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, including: windows), configuration: config)
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw Failure(message: "Could not encode the diagnostic screenshot")
                }
                let name = "\(angle)-\(mode.rawValue).png"
                try png.write(to: output.appendingPathComponent(name))
                print("diagnostic \(name)")
            }
        }
        print("✓ Five isolated render states at 80°, 60°, 40°: \(output.path)")
    }
}

private final class BlurLayerFixture: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.20, blue: 0.48, alpha: 1),
                            NSColor(srgbRed: 0.73, green: 0.18, blue: 0.26, alpha: 1),
                            NSColor(srgbRed: 0.92, green: 0.78, blue: 0.24, alpha: 1)])?
            .draw(in: bounds, angle: 18)
        let blocks: [(CGRect, NSColor)] = [
            (CGRect(x: 0.10, y: 0.62, width: 0.27, height: 0.26), .white),
            (CGRect(x: 0.58, y: 0.57, width: 0.31, height: 0.29), .black),
            (CGRect(x: 0.17, y: 0.18, width: 0.21, height: 0.23), .systemGreen),
            (CGRect(x: 0.66, y: 0.14, width: 0.18, height: 0.21), .systemPurple)
        ]
        for (unit, color) in blocks {
            color.setFill()
            CGRect(x: unit.minX * bounds.width, y: unit.minY * bounds.height,
                   width: unit.width * bounds.width, height: unit.height * bounds.height).fill()
        }
    }
}
