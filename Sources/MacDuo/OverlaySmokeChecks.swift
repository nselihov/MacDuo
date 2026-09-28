import AppKit
import MacDuoCore
import MacDuoSkyLight

/// Opt-in checks for the same renderer in its two presentation contexts.
/// Uses no screen capture and never locks or sleeps the computer.
@MainActor
enum OverlaySmokeChecks {
    private struct Failure: Error { let message: String }

    static func runLiveBlur() async throws {
        guard (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true else {
            throw Failure(message: "Unlock the desktop to check both presentation contexts")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        for presentation in FoldOverlaySurface.Presentation.allCases {
            try await checkLifecycle(presentation)
        }
        try await checkPreview()
        print("✓ Shared fullscreen checks: both contexts, blur/mask, reuse, reversal, sleep preparation, endpoint, independent release")
    }

    static func run() async throws { try await checkLifecycle(.desktop) }

    private static func checkPreview() async throws {
        let preview = FoldPreviewView(frameStore: DesktopFrameStore())
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 660, height: 416),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.level = .init(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        window.contentView = preview
        preview.update(parameters: FoldMotionModel.parameters(angle: 80, velocity: 0),
                       tuning: .standard, hasDesktopFrame: false)
        window.orderFrontRegardless()
        defer { window.close() }
        for _ in 0..<30 {
            if preview.hasRenderedFrame { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard preview.hasRenderedFrame else {
            throw Failure(message: "Preview not rendered: bounds=\(preview.bounds), visible=\(window.occlusionState.contains(.visible))")
        }
        print("✓ Small preview rendered with the shared mask and optical settings")
    }

    private static func checkLifecycle(_ presentation: FoldOverlaySurface.Presentation) async throws {
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }) else { throw Failure(message: "No active built-in display") }
        let bridge = try SkyLightBridge()
        let surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: presentation)
        surface.onEvent = { print("shared-check \(presentation): \($0)") }
        defer { surface.close(); bridge.close() }
        let windowID = surface.window.windowNumber
        var tuning = EffectTuning.standard
        tuning.responseSeconds = 0.12
        for pass in 1...2 {
            try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: 65, velocity: 0), tuning: tuning)
            try await Task.sleep(nanoseconds: 900_000_000)
            guard surface.isPresented, surface.radius > 10, surface.progress > 0.4,
                  surface.window.ignoresMouseEvents, !surface.window.canBecomeKey,
                  surface.window.canBecomeVisibleWithoutLogin == (presentation == .lockScreen) else {
                throw Failure(message: "Shared effect did not activate passively in \(presentation)")
            }
            if pass == 1 {
                surface.retire(tuning: tuning)
                try await Task.sleep(nanoseconds: 33_000_000)
                guard surface.isPresented, surface.radius > 0 else {
                    throw Failure(message: "Retirement snapped instead of settling")
                }
                try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: 50, velocity: 0), tuning: tuning)
                guard surface.window.windowNumber == windowID, surface.window.alphaValue > 0.99 else {
                    throw Failure(message: "Reversal recreated or flashed the shared window")
                }
                surface.parkForSleep()
                try await Task.sleep(nanoseconds: 100_000_000)
                guard surface.isPresented, surface.window.windowNumber == windowID else {
                    throw Failure(message: "Sleep preparation lost the submitted window")
                }
                surface.resumeAfterSleep()
            }
            surface.retire(tuning: tuning)
            for _ in 0..<90 {
                if !surface.isPresented { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard !surface.isPresented, surface.window.windowNumber == windowID else {
                throw Failure(message: "Shared effect did not release/reuse its window")
            }
        }
        try surface.show(on: screen, parameters: FoldMotionModel.parameters(angle: 95, velocity: 0), tuning: .standard, immediate: true)
        surface.parkForSleep()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        guard surface.leaseReleasedWindow else { throw Failure(message: "WindowServer lease did not release a stalled overlay") }
        surface.resumeAfterSleep()
        guard !surface.leaseReleasedWindow else { throw Failure(message: "Window lease did not recover") }
        surface.retire(tuning: .standard)
        try await Task.sleep(nanoseconds: 800_000_000)
        guard !surface.isPresented else { throw Failure(message: "Recovered window did not retire") }
        print("✓ Shared renderer lifecycle: \(presentation)")
    }
}
