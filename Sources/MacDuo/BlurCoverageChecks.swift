import AppKit
import ScreenCaptureKit
import MacDuoCore
import MacDuoSkyLight

/// Opt-in visual regression fixture. Captures only our synthetic checkerboard
/// and overlay on an unlocked desktop, never the desktop or login contents.
@MainActor
enum BlurCoverageChecks {
    private struct Failure: Error { let message: String }

    static func run() async throws {
        guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
            throw Failure(message: "Unlock the desktop for the synthetic fixture; lock-screen capture is not attempted")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw Failure(message: "Existing Screen Recording permission is needed for the fixture")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }), let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw Failure(message: "No active built-in display")
        }
        let fixtureBridge = try SkyLightBridge()
        let fixture = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        // Above ordinary content, below either fullscreen presentation context.
        fixture.level = .init(rawValue: Int(Int32.max - 3))
        fixture.hasShadow = false
        fixture.ignoresMouseEvents = true
        fixture.contentView = CheckerboardView(frame: NSRect(origin: .zero, size: screen.frame.size))
        try fixtureBridge.present(fixture)
        fixture.displayIfNeeded()
        let bridge = try SkyLightBridge()
        let surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: .lockScreen)
        var activeSurface = surface
        defer { surface.close(); bridge.close(); fixture.close(); fixtureBridge.close() }
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("blur-coverage")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        func capture(_ name: String, includeOverlay: Bool) async throws -> NSBitmapImageRep {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
                throw Failure(message: "Desktop locked during the fixture; capture stopped")
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw Failure(message: "Fixture display unavailable")
            }
            let ids = [CGWindowID(fixture.windowNumber)] + (includeOverlay ? [CGWindowID(activeSurface.window.windowNumber)] : [])
            let windows = content.windows.filter { ids.contains($0.windowID) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            guard windows.count == ids.count else { throw Failure(message: "Only owned fixture windows may be captured; a window is unavailable") }
            print("fixture \(name): \(windows.map { "\($0.windowID) visible=\($0.isOnScreen) frame=\($0.frame)" }.joined(separator: "; "))")
            let filter = SCContentFilter(display: display, including: windows)
            let config = SCStreamConfiguration()
            config.width = 1200
            config.height = Int(1200 * screen.frame.height / screen.frame.width)
            config.showsCursor = false
            config.ignoreShadowsDisplay = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "PNG unavailable") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            return bitmap
        }
        let sharp = try await capture("sharp", includeOverlay: false)
        try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: 80, velocity: 0), tuning: .standard, immediate: true)
        surface.setDiagnosticMode(.backdropsOnly)
        let blur80 = try await capture("blur-80", includeOverlay: true)
        try checkBlurSpread(blur80, sharp: sharp, angle: 80)
        surface.setDiagnosticMode(.full)
        let covered = try await capture("full-area-alpha", includeOverlay: true)
        print("✓ Blur grows from the hinge toward the free edge; artifacts: \(output.path)")

        var previousWidth = try checkTopTransition(covered, label: "80 degrees")
        try checkSideVoids(covered, angle: 80)
        var reference = [80: covered]
        for angle in [60.0, 40.0] {
            try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: angle, velocity: 0),
                             tuning: .standard, immediate: true)
            surface.setDiagnosticMode(.backdropsOnly)
            let blur = try await capture("blur-\(Int(angle))", includeOverlay: true)
            try checkBlurSpread(blur, sharp: sharp, angle: Int(angle))
            surface.setDiagnosticMode(.full)
            let folded = try await capture("edge-\(Int(angle))", includeOverlay: true)
            reference[Int(angle)] = folded
            let width = try checkTopTransition(folded, label: "\(Int(angle)) degrees")
            try checkSideVoids(folded, angle: Int(angle))
            if width <= previousWidth {
                throw Failure(message: "The top dissolve must spread as the lid closes")
            }
            previousWidth = width
        }
        surface.retire(tuning: .standard)
        try await Task.sleep(nanoseconds: 800_000_000)
        guard !surface.isPresented else { throw Failure(message: "Edge dissolve did not retire at the open endpoint") }
        print("✓ Top dissolve: continuous ramp, wider with folding, clean open endpoint")

        let desktopBridge = try SkyLightBridge()
        let desktop = try FoldOverlaySurface(screen: screen, bridge: desktopBridge, presentation: .desktop)
        defer { desktop.close(); desktopBridge.close() }
        activeSurface = desktop
        for angle in [80, 60, 40] {
            try desktop.show(on: screen, parameters: FoldMotionModel.parameters(angle: Double(angle), velocity: 0),
                             tuning: .standard, immediate: true)
            let rendered = try await capture("desktop-\(angle)", includeOverlay: true)
            try compare(rendered, with: reference[angle]!, label: "\(angle) degrees")
        }
        print("✓ Desktop and lock-screen presentations match on the same owned fixture")
    }

    private static func compare(_ actual: NSBitmapImageRep, with reference: NSBitmapImageRep, label: String) throws {
        guard actual.pixelsWide == reference.pixelsWide, actual.pixelsHigh == reference.pixelsHigh else {
            throw Failure(message: "Presentation contexts rendered different sizes")
        }
        var error = 0.0, maximum = 0.0, count = 0.0
        for y in stride(from: 0, to: actual.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: actual.pixelsWide, by: 3) {
                guard let a = actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    throw Failure(message: "A fixture pixel is unavailable")
                }
                for difference in [abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                                   abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent)] {
                    let difference = Double(difference) * 255
                    error += difference
                    maximum = max(maximum, difference)
                    count += 1
                }
            }
        }
        print("context parity \(label): mean error=\(error / count), maximum=\(maximum) of 255")
        guard error / count < 0.5, maximum < 8 else {
            throw Failure(message: "Desktop optics diverged from the lock-screen reference")
        }
    }

    /// Measure the actual WindowServer composite across the width, so the
    /// checkerboard averages out while a horizontal seam remains visible.
    private static func checkTopTransition(_ image: NSBitmapImageRep, label: String) throws -> Int {
        let plateau = rowMean(image, y: image.pixelsHigh - 10)
        guard plateau > 100 else { throw Failure(message: "No bright glass interior for the edge check") }
        let rawProfile = (0..<(image.pixelsHigh - 1)).map { y -> Double in
            rowMean(image, y: y)
        }
        // Average one checker period to measure the optical ramp rather than
        // the source pattern's horizontal stripes.
        let profile = rawProfile.indices.map { y -> Double in
            let lower = max(0, y - 18), upper = min(rawProfile.count, y + 19)
            return rawProfile[lower..<upper].reduce(0, +) / Double(upper - lower)
        }
        guard let lower = profile.firstIndex(where: { $0 > plateau * 0.1 }),
              let upper = profile.firstIndex(where: { $0 > plateau * 0.9 }) else {
            throw Failure(message: "The top ramp never reaches the clear interior")
        }
        let steps = zip(profile, profile.dropFirst()).map { $1 - $0 }
        let width = upper - lower
        let largestStep = steps.max() ?? 255
        let largestReversal = -(steps.min() ?? -255)
        let rawStep = zip(rawProfile[lower..<upper], rawProfile[(lower + 1)...upper])
            .map { abs($1 - $0) }.max() ?? 255
        print("edge \(label): 10–90% width=\(width) px, largest step=\(largestStep), reversal=\(largestReversal)")
        guard profile[0] < 2, width >= 40, largestStep < 5, largestReversal < 5, rawStep < 20 else {
            throw Failure(message: "Top edge has a hard cut, a bright seam or an insufficient dissolve")
        }
        return width
    }

    private static func checkBlurSpread(_ image: NSBitmapImageRep, sharp: NSBitmapImageRep, angle: Int) throws {
        let progress = FoldMotionModel.parameters(angle: Double(angle), velocity: 0).progress
        let projected = FoldGlassGeometry.project(.init(x: 0.5, y: 0.55), progress: progress, tuning: .standard)
        let upperY = 1 - projected.y
        let lowerY = 0.86
        for x in [0.25, 0.5, 0.75] {
            let baselineUpper = statistics(sharp, x: x, y: upperY)
            let blurredUpper = statistics(image, x: x, y: upperY)
            let baselineLower = statistics(sharp, x: x, y: lowerY)
            let blurredLower = statistics(image, x: x, y: lowerY)
            print("spread \(angle)° x=\(x): upper \(baselineUpper.deviation) → \(blurredUpper.deviation), lower \(baselineLower.deviation) → \(blurredLower.deviation)")
            guard baselineUpper.deviation > 20, baselineLower.deviation > 20,
                  blurredUpper.deviation < baselineUpper.deviation * 0.7,
                  blurredUpper.mean > 20,
                  blurredLower.deviation > blurredUpper.deviation + 15,
                  blurredLower.deviation < baselineLower.deviation * 0.95,
                  blurredUpper.alpha > 0.98, blurredLower.alpha > 0.98 else {
                throw Failure(message: "Blur does not increase from the hinge toward the free edge at \(angle)°")
            }
        }
    }

    private static func checkSideVoids(_ image: NSBitmapImageRep, angle: Int) throws {
        let progress = FoldMotionModel.parameters(angle: Double(angle), velocity: 0).progress
        let top = FoldGlassGeometry.project(.init(x: 0.5, y: 1), progress: progress, tuning: .standard).y
        let y = 1 - top * 0.55
        let middle = statistics(image, x: 0.5, y: y).mean
        let left = statistics(image, x: 0.035, y: y).mean
        let right = statistics(image, x: 0.965, y: y).mean
        print("side shadows \(angle)°: left=\(left), middle=\(middle), right=\(right)")
        guard middle > 40, left < middle * 0.5, right < middle * 0.5 else {
            throw Failure(message: "The side edges are not darkened at \(angle)°")
        }
    }

    private static func rowMean(_ image: NSBitmapImageRep, y: Int) -> Double {
        let values = (image.pixelsWide / 5 ..< image.pixelsWide * 4 / 5).compactMap { x in
            image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB).map { Double($0.redComponent) * 255 }
        }
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    private static func statistics(_ image: NSBitmapImageRep, x: Double, y: Double) -> (mean: Double, deviation: Double, alpha: Double) {
        let cx = Int(x * Double(image.pixelsWide)), cy = Int(y * Double(image.pixelsHigh))
        var values: [Double] = []
        var alpha = 0.0
        for py in (cy - 25)..<(cy + 25) {
            for px in (cx - 25)..<(cx + 25) {
                if let color = image.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) {
                    values.append(Double(color.redComponent) * 255)
                    alpha += Double(color.alphaComponent)
                }
            }
        }
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        return (mean, sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(values.count, 1))),
                alpha / Double(max(values.count, 1)))
    }
}

private final class CheckerboardView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let cell: CGFloat = 36
        for y in 0...Int(bounds.height / cell) {
            for x in 0...Int(bounds.width / cell) {
                NSColor(srgbRed: (x + y).isMultiple(of: 2) ? 0.15 : 0.85,
                        green: (x + y).isMultiple(of: 2) ? 0.15 : 0.85,
                        blue: (x + y).isMultiple(of: 2) ? 0.15 : 0.85, alpha: 1).setFill()
                NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell).fill()
            }
        }
    }
}
