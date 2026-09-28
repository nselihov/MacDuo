import AppKit
import MacDuoSkyLight
import QuartzCore

private let arguments = CommandLine.arguments
private let isPreview = arguments.contains("--preview")
private let logURL: URL = {
    if let index = arguments.firstIndex(of: "--log"), arguments.indices.contains(index + 1) {
        return URL(fileURLWithPath: arguments[index + 1])
    }
    return FileManager.default.temporaryDirectory.appendingPathComponent("MacDuoLockScreenProbe.log")
}()

private func record(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    print(line, terminator: "")
    guard let data = line.data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
    if let file = try? FileHandle(forWritingTo: logURL) {
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }
}

private final class PassivePanel: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var bridge: SkyLightBridge?
    private var panel: PassivePanel?
    private var status: NSStatusItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var presentation: Task<Void, Never>?
    private var expiresAt = Date.distantFuture
    private var visibleUntil: Date?
    private var lastTrigger = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        record("START mode=\(isPreview ? "preview" : "armed") os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        do { bridge = try SkyLightBridge() }
        catch { fail(error); return }
        record("BRIDGE symbols resolved")

        if !isPreview {
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status?.button?.title = "Duo Test"
            let menu = NSMenu()
            menu.addItem(withTitle: "Показать маркер на 8 секунд", action: #selector(preview), keyEquivalent: "")
            menu.addItem(withTitle: "Завершить проверку", action: #selector(quit), keyEquivalent: "")
            for item in menu.items { item.target = self }
            status?.menu = menu
            record("MENU ready")
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.conceal("willSleep") }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.trigger("didWake") }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.trigger("screensDidWake") }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.conceal("screensDidSleep") }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.trigger("screenIsLocked") }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.conceal("screenIsUnlocked") }

        // Wall-clock deadlines also expire while the computer is asleep.
        expiresAt = Date().addingTimeInterval(isPreview ? 10 : 15 * 60)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date() >= self.expiresAt { self.quit(); return }
                if let deadline = self.visibleUntil, Date() >= deadline { self.conceal("8-second timeout") }
            }
        }
        if isPreview { trigger("preview") }
        else { record("ARMED for 15 minutes. Waiting for user lock / lid sleep / wake. No automatic lock.") }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    @objc private func preview() { trigger("menu preview") }

    private func trigger(_ reason: String) {
        record("EVENT \(reason)")
        guard Date() < expiresAt else { quit(); return }
        // Wake commonly emits multiple events. Keep one bounded presentation.
        guard Date().timeIntervalSince(lastTrigger) > 1 else { return }
        lastTrigger = Date()
        presentation?.cancel()
        presentation = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay: UInt64 in [0, 150_000_000, 250_000_000, 400_000_000, 700_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, Date() < self.expiresAt else { return }
                guard let screen = Self.builtInScreen() else { continue }
                do {
                    self.concealWindow()
                    let panel = self.makePanel(on: screen)
                    self.panel = panel
                    try self.bridge?.present(panel)
                    self.visibleUntil = Date().addingTimeInterval(8)
                    record("PRESENT requested reason=\(reason) window=\(panel.windowNumber) screen=\(screen.localizedName). Visual confirmation required.")
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled, self.panel === panel else { return }
                    record("SPACES \(self.bridge?.membershipDescription(panel) ?? "bridge unavailable")")
                } catch { self.fail(error) }
                return
            }
            record("SKIPPED: no active separate built-in screen")
        }
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = CGDirectDisplayID(number.uint32Value)
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }
    }

    private func makePanel(on screen: NSScreen) -> PassivePanel {
        // A small corner panel cannot obscure the password form, even if rendering stalls.
        let frame = NSRect(x: screen.frame.minX + 28, y: screen.frame.minY + 40, width: 360, height: 94)
        let panel = PassivePanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = .init(rawValue: Int(Int32.max - 2))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.86).cgColor
        view.layer?.cornerRadius = 18
        let title = NSTextField(labelWithString: "MacDuo · проверка локскрина")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: 20, y: 53, width: 325, height: 22)
        view.addSubview(title)
        let subtitle = NSTextField(labelWithString: "Маркер исчезнет через 8 секунд")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .lightGray
        subtitle.frame = NSRect(x: 20, y: 29, width: 325, height: 18)
        view.addSubview(subtitle)
        let dot = CALayer()
        dot.backgroundColor = NSColor.systemMint.cgColor
        dot.cornerRadius = 3
        dot.frame = CGRect(x: 20, y: 14, width: 32, height: 5)
        view.layer?.addSublayer(dot)
        let motion = CABasicAnimation(keyPath: "transform.translation.x")
        motion.fromValue = 0
        motion.toValue = 288
        motion.duration = 1.2
        motion.autoreverses = true
        motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(motion, forKey: "probe-motion")
        panel.contentView = view
        return panel
    }

    private func concealWindow() {
        visibleUntil = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        bridge?.conceal()
    }

    private func conceal(_ reason: String) {
        presentation?.cancel()
        presentation = nil
        lastTrigger = .distantPast
        concealWindow()
        record("HIDE \(reason)")
    }

    private func fail(_ error: Error) {
        record("FAILED \(error)")
        quit()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        conceal("exit")
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
        bridge?.close()
        record("STOP")
    }
}

if arguments.contains("--check") {
    do {
        _ = try SkyLightBridge()
        record("CHECK OK: all 8 SkyLight symbols resolved. No windows created; lock-screen compatibility is not proven.")
    } catch {
        record("CHECK FAILED: \(error)")
        exit(1)
    }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = ProbeDelegate()
        application.delegate = delegate
        application.run()
    }
}
