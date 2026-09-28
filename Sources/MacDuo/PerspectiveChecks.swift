import AppKit
import MacDuoCore
import MacDuoSkyLight
import ScreenCaptureKit

/// Tracks known colored landmarks inside the projected live layer. They move
/// with the fold while staying closer to their original screen positions.
@MainActor
enum PerspectiveChecks {
    private struct Failure: Error { let message: String }
    static func run() async throws {
        func requireUnlocked() throws {
            guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
                throw Failure(message: "Unlock the desktop for the owned perspective fixture")
            }
        }
        try requireUnlocked()
        guard CGPreflightScreenCaptureAccess() else { throw Failure(message: "Existing capture permission required") }
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }), let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw Failure(message: "No active built-in screen")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let fixtureBridge = try SkyLightBridge()
        let fixture = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.ignoresMouseEvents = true
        fixture.hasShadow = false
        fixture.level = .init(rawValue: Int(Int32.max - 3))
        let landmarks = ProjectionLandmarks(frame: NSRect(origin: .zero, size: screen.frame.size))
        fixture.contentView = landmarks
        try fixtureBridge.present(fixture)
        defer { fixture.close(); fixtureBridge.close() }
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("perspective-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var reference: [String: [CGPoint]] = [:]
        for presentation in FoldOverlaySurface.Presentation.allCases {
            let bridge = try SkyLightBridge()
            let surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: presentation)
            defer { surface.close(); bridge.close() }
            // Closing, updating the live source at a fixed angle, and reopening.
            let phases: [(Double, CGPoint)] = [(0.35, .zero), (0.6, .zero),
                                               (0.6, CGPoint(x: 0.03, y: 0.04)), (0.35, .zero)]
            for (progress, offset) in phases {
                landmarks.offset = offset
                landmarks.needsDisplay = true
                let key = "\(progress)-\(offset.x)"
                let params = FoldParameters(progress: progress, tiltDegrees: progress * 82, blurRadius: 5 / 0.45,
                                            blurBlend: 1, brightnessOffset: 0, glassIntensity: 0, topShadeOpacity: 0, topDissolve: 0)
                try surface.show(on: screen, parameters: params, tuning: .standard, immediate: true)
                surface.setDiagnosticMode(.projectedOnly)
                try await Task.sleep(nanoseconds: 400_000_000)
                try requireUnlocked()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure(message: "Display missing") }
                let ids = [CGWindowID(fixture.windowNumber), CGWindowID(surface.window.windowNumber)]
                let windows = content.windows.filter { ids.contains($0.windowID) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
                guard windows.count == 2 else { throw Failure(message: "Owned windows missing") }
                let config = SCStreamConfiguration()
                config.width = 1200; config.height = Int(1200 * screen.frame.height / screen.frame.width)
                config.showsCursor = false; config.ignoreShadowsDisplay = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: windows), configuration: config)
                let bitmap = NSBitmapImageRep(cgImage: image)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: output.appendingPathComponent("\(presentation)-\(key).png"))
                }
                var centers: [CGPoint] = []
                for (index, marker) in ProjectionLandmarks.markers.enumerated() {
                    let source = FoldGlassGeometry.Point(x: marker.point.x + offset.x, y: marker.point.y + offset.y)
                    let point = FoldProjectionMesh.displayPoint(for: source, progress: progress,
                                                                 tuning: .standard)
                    let expected = CGPoint(x: point.x * Double(bitmap.pixelsWide), y: (1 - point.y) * Double(bitmap.pixelsHigh))
                    if index == 2, offset == .zero {
                        let original = CGPoint(x: source.x * Double(bitmap.pixelsWide),
                                               y: (1 - source.y) * Double(bitmap.pixelsHigh))
                        let folded = FoldGlassGeometry.project(source, progress: progress,
                                                                 tuning: .standard)
                        let fullProjection = CGPoint(x: folded.x * Double(bitmap.pixelsWide),
                                                     y: (1 - folded.y) * Double(bitmap.pixelsHigh))
                        let anchoredTravel = hypot(expected.x - original.x, expected.y - original.y)
                        let fullTravel = hypot(fullProjection.x - original.x,
                                               fullProjection.y - original.y)
                        guard anchoredTravel > 5, anchoredTravel < fullTravel * 0.8 else {
                            throw Failure(message: "The image lost perspective or no longer stays near its original position")
                        }
                    }
                    var sumX = 0.0, sumY = 0.0, count = 0.0
                    let cx = Int(expected.x), cy = Int(expected.y)
                    for y in stride(from: max(cy - 60, 0), through: min(cy + 60, bitmap.pixelsHigh - 1), by: 2) {
                        for x in stride(from: max(cx - 60, 0), through: min(cx + 60, bitmap.pixelsWide - 1), by: 2) {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                            let matches: Bool
                            switch index {
                            case 0: matches = r > 0.4 && r > g * 1.8 && r > b * 1.8
                            case 1: matches = g > 0.4 && g > r * 1.8 && g > b * 1.8
                            case 2: matches = b > 0.4 && b > r * 1.8 && b > g * 1.5
                            default: matches = r > 0.4 && b > 0.4 && r > g * 1.8 && b > g * 1.8
                            }
                            if matches { sumX += Double(x); sumY += Double(y); count += 1 }
                        }
                    }
                    guard count > 30 else { throw Failure(message: "Projected landmark \(index) is missing") }
                    let center = CGPoint(x: sumX / count, y: sumY / count)
                    let error = hypot(center.x - expected.x, center.y - expected.y)
                    print("landmark \(presentation) p=\(progress) offset=\(offset) #\(index): center=\(center), expected=\(expected), error=\(error) px")
                    guard error < 4 else { throw Failure(message: "Content did not follow the projection at landmark \(index)") }
                    centers.append(center)
                }
                if let previous = reference[key] {
                    for (a, b) in zip(centers, previous) {
                        guard hypot(a.x - b.x, a.y - b.y) < 1 else { throw Failure(message: "Contexts or reversal diverged") }
                    }
                } else { reference[key] = centers }

                // The isolated projected layer is insufficient: the complete
                // effect must carry the screen image, including the hinge end.
                surface.setDiagnosticMode(.full)
                try await Task.sleep(nanoseconds: 250_000_000)
                let fullImage = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, including: windows),
                    configuration: config)
                let full = NSBitmapImageRep(cgImage: fullImage)
                if let png = full.representation(using: .png, properties: [:]) {
                    try png.write(to: output.appendingPathComponent("full-\(presentation)-\(key).png"))
                }
                for index in 0..<2 {
                    let expected = centers[index]
                    var sumX = 0.0, sumY = 0.0, count = 0.0
                    for y in stride(from: max(Int(expected.y) - 35, 0), through: min(Int(expected.y) + 35, full.pixelsHigh - 1), by: 2) {
                        for x in stride(from: max(Int(expected.x) - 35, 0), through: min(Int(expected.x) + 35, full.pixelsWide - 1), by: 2) {
                            guard let color = full.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                            let matches = index == 0 ? r > 0.4 && r > g * 1.8 && r > b * 1.8
                                                     : g > 0.4 && g > r * 1.8 && g > b * 1.8
                            if matches { sumX += Double(x); sumY += Double(y); count += 1 }
                        }
                    }
                    guard count > 30 else { throw Failure(message: "Full effect hid lower screen landmark \(index)") }
                    let measured = CGPoint(x: sumX / count, y: sumY / count)
                    let error = hypot(measured.x - expected.x, measured.y - expected.y)
                    print("full image \(presentation) p=\(progress) #\(index): error=\(error) px")
                    guard error < 4 else { throw Failure(message: "The mask moved but the lower screen image did not") }
                }
            }
            surface.retire(tuning: .standard)
            try await Task.sleep(nanoseconds: 800_000_000)
            guard !surface.isPresented else { throw Failure(message: "Projected window did not retire") }
        }
        print("✓ Perspective content: four landmarks follow the fold through closing/opening and both presentation contexts. Artifacts: \(output.path)")
    }
}

private final class ProjectionLandmarks: NSView {
    var offset = CGPoint.zero
    struct Marker { let point: FoldGlassGeometry.Point; let color: NSColor }
    static let markers: [Marker] = [
        Marker(point: .init(x: 0.25, y: 0.20), color: NSColor(srgbRed: 0.9, green: 0.12, blue: 0.1, alpha: 1)),
        Marker(point: .init(x: 0.75, y: 0.20), color: NSColor(srgbRed: 0.1, green: 0.8, blue: 0.15, alpha: 1)),
        Marker(point: .init(x: 0.25, y: 0.65), color: NSColor(srgbRed: 0.12, green: 0.25, blue: 0.95, alpha: 1)),
        Marker(point: .init(x: 0.75, y: 0.65), color: NSColor(srgbRed: 0.9, green: 0.15, blue: 0.8, alpha: 1))
    ]
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1).setFill(); bounds.fill()
        NSColor.white.withAlphaComponent(0.2).setStroke()
        let grid = NSBezierPath()
        for i in 1..<8 {
            let x = CGFloat(i) * bounds.width / 8, y = CGFloat(i) * bounds.height / 8
            grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: bounds.height))
            grid.move(to: CGPoint(x: 0, y: y)); grid.line(to: CGPoint(x: bounds.width, y: y))
        }
        grid.stroke()
        for marker in Self.markers {
            marker.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: (marker.point.x + offset.x) * bounds.width - 40, y: (marker.point.y + offset.y) * bounds.height - 40,
                                       width: 80, height: 80)).fill()
        }
    }
}
