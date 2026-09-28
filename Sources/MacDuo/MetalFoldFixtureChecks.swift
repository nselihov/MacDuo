import AppKit
import CoreImage
import CoreVideo
import MacDuoCore
import MacDuoSkyLight
import ScreenCaptureKit

/// Opt-in visual check of the experimental MTKView on an owned synthetic image.
/// The capture filter includes only the renderer window, never desktop windows.
@MainActor
enum MetalFoldFixtureChecks {
    private struct Failure: Error { let message: String }

    static func run() async throws {
        let frameStore = DesktopFrameStore()
        frameStore.update(try makePattern())
        try await captureAngles(frameStore: frameStore, directoryName: "metal-fold-fixture")
    }

    static func runLive(model: AppModel) async throws {
        model.connectDesktop()
        for _ in 0..<100 {
            if model.hasDesktopFrame { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard model.hasDesktopFrame else {
            throw Failure(message: "Live desktop frame did not arrive")
        }
        if let snapshot = model.desktopFrameStore.snapshot() {
            let output = Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("metal-fold-live")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let image = CIImage(cvPixelBuffer: snapshot.pixelBuffer)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(image, from: image.extent),
                  let png = NSBitmapImageRep(cgImage: cgImage)
                    .representation(using: .png, properties: [:]) else {
                throw Failure(message: "Could not save the captured source frame")
            }
            try png.write(to: output.appendingPathComponent("source.png"))
        }
        try await captureAngles(frameStore: model.desktopFrameStore,
                                directoryName: "metal-fold-live")
    }

    private static func captureAngles(frameStore: DesktopFrameStore,
                                      directoryName: String) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw Failure(message: "Existing Screen Recording permission is required")
        }
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }), let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw Failure(message: "No active built-in display")
        }

        let bridge = try SkyLightBridge()
        let surface = try MetalFoldOverlaySurface(screen: screen, bridge: bridge, frameStore: frameStore)
        // Synthetic input has no capture loop, so allow ScreenCaptureKit to
        // photograph the output. Live input must keep this window unshareable.
        if directoryName == "metal-fold-fixture" { surface.window.sharingType = .readOnly }
        defer { surface.close(); bridge.close() }
        let output = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cleanSnapshot = directoryName == "metal-fold-live" ? frameStore.snapshot() : nil
        let cleanInput = cleanSnapshot?.pixelBuffer
        var previousGeneration = cleanSnapshot?.generation ?? 0

        for angle in [80.0, 60.0, 40.0] {
            try surface.show(on: screen,
                             parameters: FoldMotionModel.parameters(angle: angle, velocity: 0),
                             tuning: .standard)
            try await Task.sleep(nanoseconds: 850_000_000)
            let visibleWindows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly], kCGNullWindowID
            ) as? [[String: Any]] ?? []
            guard visibleWindows.contains(where: {
                ($0[kCGWindowNumber as String] as? Int) == surface.window.windowNumber
            }) else {
                throw Failure(message: "Renderer window is not visible on screen at \(Int(angle))°")
            }
            if directoryName == "metal-fold-live", let snapshot = frameStore.snapshot() {
                guard snapshot.generation > previousGeneration else {
                    throw Failure(message: "Live capture stopped during the effect at \(Int(angle))°")
                }
                previousGeneration = snapshot.generation
                if let cleanInput {
                    let difference = meanPixelDifference(cleanInput, snapshot.pixelBuffer)
                    guard difference < 15 else {
                        throw Failure(message: "Overlay leaked into ScreenCaptureKit at \(Int(angle))°: mean difference \(difference)")
                    }
                    print("✓ Live input \(Int(angle))° generation \(snapshot.generation) excludes overlay: mean difference \(difference)")
                }
                let image = CIImage(cvPixelBuffer: snapshot.pixelBuffer)
                let context = CIContext(options: nil)
                if let cgImage = context.createCGImage(image, from: image.extent),
                   let png = NSBitmapImageRep(cgImage: cgImage)
                    .representation(using: .png, properties: [:]) {
                    try png.write(to: output.appendingPathComponent("source-after-\(Int(angle)).png"))
                }
                continue
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }),
                  let owned = content.windows.first(where: {
                      $0.windowID == CGWindowID(surface.window.windowNumber)
                          && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                  }) else {
                throw Failure(message: "Renderer window is unavailable to capture")
            }
            let filter = SCContentFilter(display: display, including: [owned])
            let config = SCStreamConfiguration()
            config.width = 1200
            config.height = Int(1200 * screen.frame.height / screen.frame.width)
            config.showsCursor = false
            config.ignoreShadowsDisplay = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw Failure(message: "PNG unavailable")
            }
            let path = output.appendingPathComponent("fold-\(Int(angle)).png")
            try png.write(to: path)
            print("✓ Metal fold fixture \(Int(angle))°: \(path.path)")
        }
    }

    private static func meanPixelDifference(_ first: CVPixelBuffer,
                                            _ second: CVPixelBuffer) -> Double {
        guard CVPixelBufferGetWidth(first) == CVPixelBufferGetWidth(second),
              CVPixelBufferGetHeight(first) == CVPixelBufferGetHeight(second),
              CVPixelBufferGetPixelFormatType(first) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetPixelFormatType(second) == kCVPixelFormatType_32BGRA else {
            return .infinity
        }
        CVPixelBufferLockBaseAddress(first, .readOnly)
        CVPixelBufferLockBaseAddress(second, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(second, .readOnly)
            CVPixelBufferUnlockBaseAddress(first, .readOnly)
        }
        guard let firstBase = CVPixelBufferGetBaseAddress(first),
              let secondBase = CVPixelBufferGetBaseAddress(second) else { return .infinity }
        let width = CVPixelBufferGetWidth(first), height = CVPixelBufferGetHeight(first)
        let firstStride = CVPixelBufferGetBytesPerRow(first)
        let secondStride = CVPixelBufferGetBytesPerRow(second)
        var total = 0.0, count = 0.0
        for y in stride(from: 16, to: height, by: 32) {
            let firstRow = firstBase.advanced(by: y * firstStride).assumingMemoryBound(to: UInt8.self)
            let secondRow = secondBase.advanced(by: y * secondStride).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 16, to: width, by: 32) {
                for channel in 0..<3 {
                    total += Double(abs(Int(firstRow[x * 4 + channel])
                                        - Int(secondRow[x * 4 + channel])))
                    count += 1
                }
            }
        }
        return total / max(count, 1)
    }

    private static func makePattern() throws -> CVPixelBuffer {
        let width = 1200, height = 800
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &result)
        guard status == kCVReturnSuccess, let result else {
            throw Failure(message: "Could not make Metal-compatible test image: \(status)")
        }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        guard let base = CVPixelBufferGetBaseAddress(result) else {
            throw Failure(message: "Test image has no writable pixels")
        }
        let stride = CVPixelBufferGetBytesPerRow(result)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let line = x % 80 < 3 || y % 80 < 3
                let band = x < width / 3 ? 0 : x < 2 * width / 3 ? 1 : 2
                let bright: UInt8 = line ? 235 : ((x / 40 + y / 40) % 2 == 0 ? 135 : 45)
                let offset = x * 4
                row[offset + 0] = band == 0 ? bright : bright / 3
                row[offset + 1] = band == 1 ? bright : bright / 3
                row[offset + 2] = band == 2 ? bright : bright / 3
                row[offset + 3] = 255
            }
        }
        return result
    }
}
