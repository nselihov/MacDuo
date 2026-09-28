import AppKit
import MacDuoCore
import QuartzCore
import MacDuoSkyLight

/// The canonical fullscreen effect, based on the accepted lock-screen renderer.
/// Both contexts use the same WindowServer presentation and optical settings.
@MainActor
final class FoldOverlaySurface {
    enum Presentation: CaseIterable { case desktop, lockScreen }
    enum DiagnosticMode: String, CaseIterable {
        case edgeOnly, projectedOnly, maskOnly, backdropsOnly, full
    }
    let window: NSWindow
    private let bridge: SkyLightBridge
    private var targetRadius = 0.0
    private(set) var radius = 0.0
    private var responseSeconds = 0.045
    private var lastTick = CACurrentMediaTime()
    private var timer: Timer?
    private var lastAppliedRadius = -1
    private let mask: FoldMaskView
    private let backdrop: ProjectedBackdropView
    private let diagnosticBackground = NSView()
    private var targetProgress = 0.0
    private(set) var progress = 0.0
    private var tuning = EffectTuning.standard
    private var lease: SkyLightWindowLease?
    private(set) var isPresented = false
    var leaseReleasedWindow: Bool { lease?.didReleaseWindow == true }
    var onEvent: ((String) -> Void)?
    private let measureFrames = CommandLine.arguments.contains("--fold-performance-check")
    private var frameIntervals: [Double] = []
    private var maskTimes: [Double] = []
    private var backdropTimes: [Double] = []

    init(screen: NSScreen, bridge: SkyLightBridge, presentation: Presentation) throws {
        self.bridge = bridge
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let systemBackdrop = try SystemBackdrop()
        backdrop = try ProjectedBackdropView(frame: bounds, backdrop: systemBackdrop)
        mask = FoldMaskView(frame: bounds)
        window = LiveBlurWindow(contentRect: screen.frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        // Preserve a continuous, minimally tinted backing for WindowServer.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.canHide = false
        window.canBecomeVisibleWithoutLogin = presentation == .lockScreen
        window.level = .init(rawValue: Int(Int32.max - 2))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        let content = NSView(frame: bounds)
        content.wantsLayer = true
        diagnosticBackground.frame = bounds
        diagnosticBackground.autoresizingMask = [.width, .height]
        diagnosticBackground.wantsLayer = true
        diagnosticBackground.layer?.backgroundColor = NSColor.systemTeal.cgColor
        diagnosticBackground.isHidden = true
        backdrop.autoresizingMask = [.width, .height]
        mask.autoresizingMask = [.width, .height]
        content.addSubview(diagnosticBackground)
        content.addSubview(backdrop)
        content.addSubview(mask)
        window.contentView = content
        try systemBackdrop.prepare(window: window)
        mask.update(progress: 0, tuning: .standard)
        backdrop.update(progress: 0, tuning: .standard)
    }

    /// Opt-in layer isolation for screenshots on an unlocked, owned fixture.
    /// It does not read or write the saved user preset.
    func setDiagnosticMode(_ mode: DiagnosticMode) {
        diagnosticBackground.isHidden = mode != .maskOnly
        backdrop.showLayers(edge: mode == .edgeOnly || mode == .backdropsOnly || mode == .full,
                            projected: mode == .projectedOnly || mode == .backdropsOnly || mode == .full,
                            reveal: mode == .full)
        mask.isHidden = mode == .edgeOnly || mode == .projectedOnly || mode == .backdropsOnly
    }

    func show(on screen: NSScreen, parameters: FoldParameters, tuning: EffectTuning,
              immediate: Bool = false) throws {
        let tuning = tuning.clamped()
        self.tuning = tuning
        responseSeconds = tuning.responseSeconds
        targetProgress = parameters.progress
        targetRadius = FoldAppearance.blurRadius(parameters: parameters, tuning: tuning)
        if immediate { radius = targetRadius; progress = targetProgress }
        if !isPresented {
            window.setFrame(screen.frame, display: false)
            window.alphaValue = immediate ? 1 : 0.001
            mask.update(progress: progress, tuning: tuning)
            backdrop.update(progress: progress, tuning: tuning)
            applyRadius()
            lease = try bridge.makeWindowLease(for: window)
            try bridge.present(window)
            isPresented = true
            lastTick = CACurrentMediaTime()
            onEvent?("live backdrop presented")
        }
        startTimer()
    }

    func retire(tuning: EffectTuning) {
        guard isPresented else { return }
        responseSeconds = tuning.clamped().responseSeconds
        targetRadius = 0
        targetProgress = 0
        startTimer()
    }

    func hideImmediately() {
        guard isPresented || lease != nil else { return }
        timer?.invalidate()
        timer = nil
        lease?.cancel()
        lease = nil
        window.alphaValue = 0
        window.orderOut(nil)
        bridge.conceal()
        let wasPresented = isPresented
        isPresented = false
        radius = 0
        targetRadius = 0
        progress = 0
        targetProgress = 0
        if wasPresented { onEvent?("live backdrop hidden") }
    }

    /// Leave the already-composited layer in place while WindowServer wakes.
    /// The lease uses awake uptime, so a normal sleep does not consume it.
    func parkForSleep() {
        timer?.invalidate()
        timer = nil
        radius = targetRadius
        progress = targetProgress
        mask.update(progress: progress, tuning: tuning)
        backdrop.update(progress: progress, tuning: tuning)
        applyRadius()
        window.alphaValue = 1
        lease?.renew(alpha: 1)
        CATransaction.flush()
        onEvent?("live fold parked for sleep")
    }

    func resumeAfterSleep() {
        guard isPresented else { return }
        lease?.renew(alpha: window.alphaValue)
        window.orderFrontRegardless()
        startTimer()
    }

    func close() { hideImmediately(); window.close() }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let interval = now - lastTick
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now
        let response = FoldAppearance.response(deltaTime: dt, responseSeconds: responseSeconds)
        radius += (targetRadius - radius) * response
        progress += (targetProgress - progress) * response
        mask.update(progress: progress, tuning: tuning)
        let afterMask = measureFrames ? CACurrentMediaTime() : 0
        backdrop.update(progress: progress, tuning: tuning)
        if measureFrames {
            frameIntervals.append(interval)
            maskTimes.append(afterMask - now)
            backdropTimes.append(CACurrentMediaTime() - afterMask)
            if frameIntervals.count == 60 {
                func p95(_ values: [Double]) -> Int {
                    let sorted = values.sorted()
                    return Int((sorted[56] * 1_000).rounded())
                }
                print("fold-frame p95 interval=\(p95(frameIntervals))ms mask=\(p95(maskTimes))ms backdrop=\(p95(backdropTimes))ms")
                frameIntervals.removeAll(keepingCapacity: true)
                maskTimes.removeAll(keepingCapacity: true)
                backdropTimes.removeAll(keepingCapacity: true)
            }
        }
        applyRadius()
        // Blend out the last few points of blur while the real screen is
        // already visible. There is no sharp wallpaper frame to swap away.
        window.alphaValue = FoldAppearance.opacity(radius: radius, progress: progress)
        lease?.renew(alpha: window.alphaValue)
        if targetRadius == 0 && radius < 0.03 && progress < 0.0001 { hideImmediately() }
    }

    private func applyRadius() {
        let rounded = Int(max(radius.rounded(), 1))
        guard rounded != lastAppliedRadius else { return }
        backdrop.setRadius(Double(rounded))
        lastAppliedRadius = rounded
    }

    deinit { timer?.invalidate(); lease?.cancel() }
}

private final class LiveBlurWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
