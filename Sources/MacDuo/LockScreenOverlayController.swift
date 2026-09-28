import AppKit
import MacDuoCore
import MacDuoSkyLight
import QuartzCore

@MainActor
final class LockScreenOverlayController {
    private weak var model: AppModel?
    private var bridge: SkyLightBridge?
    private var surface: FoldOverlaySurface?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var gate = LockScreenMotionGate()
    private var wakeGate = WakeMotionGate()
    private var openStop = LockScreenOpenStop()
    private var enabled = false
    private var locked = false
    private var suspended = false
    private var latestAngle: Double?
    private var lockedSampleCount = 0
    private var previewStartedAt: Double?
    private var wakeStartedAt: Double?
    private var receivedWakeSample = false
    private var preparedDisplay: Display?
    private var lastScreen: NSScreen?
    private var parkedForSleep = false

    private struct Display: Equatable {
        let id: UInt32
        let frame: NSRect
        let scale: CGFloat
    }

    init(model: AppModel) {
        self.model = model
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.sleep("willSleep") }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.sleep("displaySleep") }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.wake("didWake") }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.wake("displayWake") }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            if let self, !self.suspended, !Self.screenIsLocked {
                self.locked = false
                self.hide("inactive session")
            }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self, self.enabled else { return }
            // During actual sleep the built-in display can temporarily vanish.
            // Keep the already-submitted layer for its first frame after wake.
            guard !self.suspended else { return }
            guard let screen = Self.builtInScreen() else {
                // The first display-wake callback can precede NSScreen's graph.
                if self.parkedForSleep && self.wakeStartedAt != nil,
                   let id = self.preparedDisplay?.id, CGDisplayIsInMirrorSet(id) == 0 { return }
                self.hide("display unavailable")
                return
            }
            if self.preparedDisplay != Self.display(screen) {
                self.hide("display changed")
                self.prepareSurface(on: screen)
            }
            if self.locked { self.startTimer(); self.refreshMotion() }
        }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { [weak self] in
            self?.hide("exit")
            self?.surface?.close()
            self?.bridge?.close()
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            guard let self else { return }
            self.locked = true
            self.previewStartedAt = nil
            self.gate.invalidate()
            self.lockedSampleCount = 0
            self.log("screen locked")
            self.startTimer()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            guard let self else { return }
            self.locked = false
            self.gate.invalidate()
            self.wakeGate = WakeMotionGate()
            self.hide("unlock")
        }
    }

    func setEnabled(_ value: Bool) -> Bool {
        if value && enabled { return true }
        if !value {
            enabled = false
            hide("disabled")
            surface?.close()
            surface = nil
            bridge?.close()
            bridge = nil
            preparedDisplay = nil
            model?.setLockScreenStatus("Выключен")
            return false
        }
        do {
            let bridge = try SkyLightBridge()
            self.bridge = bridge
            enabled = true
            locked = Self.screenIsLocked
            gate.invalidate()
            wakeGate = WakeMotionGate()
            if let screen = Self.builtInScreen() { prepareSurface(on: screen) }
            if locked { startTimer() }
            log("enabled: live system backdrop + content perspective + shared glass mask")
            return true
        } catch {
            model?.setLockScreenStatus("Системный слой недоступен: \(error)")
            log("unavailable: \(error)")
            return false
        }
    }

    func receive(angle: Double) {
        latestAngle = angle
        guard enabled, !suspended else { return }
        let now = CACurrentMediaTime()
        gate.receive(angle: angle, at: now)
        let openAngle = model?.openAngle ?? 115
        wakeGate.receive(angle: angle, at: now, openAngle: openAngle)
        let wasAllowed = openStop.allowsPresentation
        let allowsPresentation = openStop.receive(angle: angle, openAngle: openAngle)
        if wasAllowed && !allowsPresentation && locked {
            gate.invalidate()
            if let model { surface?.retire(tuning: model.effectTuning) }
            log("opening completed at raw angle=\(angle)")
        } else if !wasAllowed && allowsPresentation && locked {
            log("closing rearmed at raw angle=\(angle)")
        }
        if let start = wakeStartedAt, !receivedWakeSample {
            receivedWakeSample = true
            log("fresh wake sample after \(Int((CACurrentMediaTime() - start) * 1000)) ms angle=\(angle)")
        }
        if locked {
            lockedSampleCount += 1
            if lockedSampleCount == 1 { log("HID sample while locked angle=\(angle)") }
        }
    }

    func preview() {
        guard enabled, !suspended, !locked else { return }
        hide("restart preview")
        previewStartedAt = CACurrentMediaTime()
        startTimer()
        refreshMotion()
    }

    func refreshMotion() {
        guard enabled, !suspended, let model else { return }
        let now = CACurrentMediaTime()
        if let wakeStart = wakeStartedAt {
            if receivedWakeSample {
                wakeStartedAt = nil
                parkedForSleep = false
                if !locked { surface?.retire(tuning: model.effectTuning) }
            } else if now - wakeStart < 0.4 {
                return // The pre-sleep layer is already on screen, not shown later.
            } else {
                wakeStartedAt = nil
                parkedForSleep = false
                surface?.retire(tuning: model.effectTuning)
                log("wake sensor deadline: releasing prepared layer")
            }
        }
        guard locked || previewStartedAt != nil else {
            timer?.invalidate()
            timer = nil
            return
        }
        if previewStartedAt == nil &&
           (!wakeGate.allowsMotion(at: now) || !openStop.allowsPresentation) {
            surface?.retire(tuning: model.effectTuning)
            return
        }
        let parameters: FoldParameters
        let shouldShow: Bool
        if let start = previewStartedAt {
            let elapsed = now - start
            if elapsed >= 3 {
                previewStartedAt = nil
                timer?.invalidate()
                timer = nil
                surface?.retire(tuning: model.effectTuning)
                return
            }
            let progress = pow(sin(.pi * elapsed / 3), 2) * 0.8
            parameters = FoldMotionModel.parameters(
                angle: model.openAngle - progress * (model.openAngle - model.closedAngle),
                velocity: 0, openAngle: model.openAngle, closedAngle: model.closedAngle)
            shouldShow = surface?.isPresented == true
                ? FoldMotionModel.shouldKeepOverlayVisible(for: parameters)
                : FoldMotionModel.shouldPresentOverlay(for: parameters)
        } else {
            parameters = model.sensorFoldParameters
            shouldShow = gate.shouldShow(parameters: parameters, at: now)
        }
        guard shouldShow else {
            if locked, surface?.isPresented == true, let latestAngle {
                // If HID samples stop, the motion gate retires the layer before
                // the lid reaches its calibrated open angle. Do not replay
                // that same opening when samples resume a moment later.
                wakeGate.suppressUntilClosing(from: latestAngle)
                log("lock-screen pass retired at raw angle=\(latestAngle); waiting for closing")
            }
            surface?.retire(tuning: model.effectTuning)
            return
        }
        guard let screen = Self.builtInScreen() else { return }
        if preparedDisplay != Self.display(screen) || surface == nil {
            surface?.hideImmediately()
            prepareSurface(on: screen)
        }
        do {
            if locked && surface?.isPresented != true {
                log("present rawAngle=\(latestAngle ?? -1) progress=\(parameters.progress)")
            }
            try surface?.show(on: screen, parameters: parameters, tuning: model.effectTuning)
        } catch {
            hide("present failed")
            model.setLockScreenStatus("Не удалось показать слой: \(error)")
            log("present failed: \(error)")
        }
    }

    private func sleep(_ reason: String) {
        log(reason)
        suspended = true
        gate.invalidate()
        previewStartedAt = nil
        wakeStartedAt = nil
        receivedWakeSample = false
        timer?.invalidate()
        timer = nil
        if parkedForSleep { surface?.parkForSleep(); return }
        guard enabled, let model,
              let screen = Self.builtInScreen() ?? lastScreen else { return }
        let parameters = FoldMotionModel.parameters(angle: latestAngle ?? model.sensorAngle, velocity: 0,
                                                     openAngle: model.openAngle, closedAngle: model.closedAngle)
        guard FoldMotionModel.shouldPresentOverlay(for: parameters) else { surface?.hideImmediately(); return }
        if surface == nil { prepareSurface(on: screen) }
        do {
            try surface?.show(on: screen, parameters: parameters, tuning: model.effectTuning, immediate: true)
            surface?.parkForSleep()
            parkedForSleep = surface?.isPresented == true
        } catch { hide("sleep preparation failed"); log("sleep preparation failed: \(error)") }
    }

    private func wake(_ reason: String) {
        log(reason)
        let wasSuspended = suspended
        suspended = false
        locked = Self.screenIsLocked || locked
        guard enabled else { return }
        if wasSuspended {
            wakeStartedAt = CACurrentMediaTime()
            wakeGate.begin(at: wakeStartedAt!)
            receivedWakeSample = false
            surface?.resumeAfterSleep()
            log("wake layer already prepared=\(parkedForSleep)")
        }
        if locked || wakeStartedAt != nil { startTimer() }
        // Duplicate wake events keep the same layer and the same deadline.
    }

    private func prepareSurface(on screen: NSScreen) {
        guard let bridge else { return }
        do {
            if surface == nil {
                let surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: .lockScreen)
                surface.onEvent = { [weak self] in self?.log($0) }
                self.surface = surface
            }
            preparedDisplay = Self.display(screen)
            lastScreen = screen
            model?.setLockScreenStatus("Живой локскрин + перспектива стекла")
            log("live surface prepared before presentation")
        } catch {
            model?.setLockScreenStatus("Живой слой недоступен: \(error)")
            log("prepare failed: \(error)")
        }
    }

    private func startTimer() {
        guard enabled, !suspended, timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMotion() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func hide(_ reason: String) {
        previewStartedAt = nil
        wakeStartedAt = nil
        parkedForSleep = false
        timer?.invalidate()
        timer = nil
        if surface?.isPresented == true { log("hide requested reason=\(reason) lockedSamples=\(lockedSampleCount)") }
        surface?.hideImmediately()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
    }

    private static var screenIsLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static func display(_ screen: NSScreen) -> Display? {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
        return Display(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first {
            guard let display = display($0) else { return false }
            return CGDisplayIsBuiltin(display.id) != 0 && CGDisplayIsActive(display.id) != 0 && CGDisplayIsInMirrorSet(display.id) == 0
        }
    }

    private func log(_ message: String) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("lock-screen-effect.log")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: data)
        }
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }
}
