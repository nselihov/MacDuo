import AppKit
import Combine
import Foundation
import MacDuoCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    enum MotionSource: String, CaseIterable, Identifiable {
        case sensor
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sensor: "Крышка"
            case .manual: "Ползунок"
            }
        }
    }

    @Published var source: MotionSource
    @Published var manualAngle = 82.0 {
        didSet { updateOverlayVisibility() }
    }
    @Published private(set) var sensorAngle = 120.0
    @Published private(set) var velocity = 0.0
    @Published private(set) var sensorStatus: String
    @Published private(set) var sensorHasSample = false
    @Published private(set) var hasDesktopFrame = false
    @Published private(set) var captureState: DesktopCaptureService.State
    @Published private(set) var isFullscreenEffectEnabled = false
    @Published private(set) var fullscreenEffectFailure: String?
    @Published private(set) var wantsDesktopConnected = false
    @Published private(set) var isSystemSuspended = false
    @Published private(set) var isUserSessionActive = true
    @Published private(set) var displayEnvironment: DesktopCaptureService.DisplayEnvironment
    @Published private(set) var openAngle = FoldMotionModel.defaultOpenAngle
    @Published private(set) var closedAngle = FoldMotionModel.defaultClosedAngle
    @Published private(set) var calibrationMessage = "Можно настроить под ход вашей крышки"
    @Published private(set) var effectTuning: EffectTuning {
        didSet {
            updateOverlayVisibility()
            lockScreenOverlay?.refreshMotion()
        }
    }
    @Published private(set) var effectPresetMessage: String
    @Published private(set) var isLockScreenEffectEnabled = false
    @Published private(set) var lockScreenStatus = "Выключен"
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginMessage = ""

    private let sensor: LidAngleSensor
    private let captureService: DesktopCaptureService
    private let motionInterpolator: MotionInterpolator
    private var overlayController: OverlayController?
    private var lockScreenOverlay: LockScreenOverlayController?
    private var overlayMotionActive = false
    private var captureActivity = DesktopCaptureActivityGate()
    private var captureRequested = false
    private var captureStopTask: Task<Void, Never>?
    private var rawSensorAngle = 120.0
    private var renderSensorAngle = 120.0
    private var renderVelocity = 0.0
    private var savedEffectTuning: EffectTuning
    private var lifecycleCancellables = Set<AnyCancellable>()
    private var recoveryTask: Task<Void, Never>?
    private var displayChangeTask: Task<Void, Never>?
    private var sensorRecoveryTask: Task<Void, Never>?

    private static let openAngleKey = "calibration.openAngle"
    private static let closedAngleKey = "calibration.closedAngle"
    private static let minimumCalibrationTravel = 20.0
    private static let effectTuningKey = "effect.tuning.v1"
    private static let lockScreenEffectKey = "experiment.lockScreen.v1"
    private static let desktopConnectionKey = "desktop.connectAtLaunch.v1"
    private static let desktopEffectKey = "desktop.effectEnabled.v1"

    init() {
        let sensor = LidAngleSensor()
        let captureService = DesktopCaptureService()
        let motionInterpolator = MotionInterpolator()
        self.sensor = sensor
        self.captureService = captureService
        self.motionInterpolator = motionInterpolator
        source = sensor.isAvailable ? .sensor : .manual
        sensorStatus = sensor.statusText
        captureState = captureService.state
        displayEnvironment = DesktopCaptureService.currentDisplayEnvironment()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        isUserSessionActive = session?["CGSSessionScreenIsLocked"] as? Bool != true

        let storedEffectTuning = Self.loadEffectTuning()
        effectTuning = storedEffectTuning
        savedEffectTuning = storedEffectTuning
        effectPresetMessage = storedEffectTuning == .standard
            ? "Базовый пресет"
            : "Сохранённый пресет загружен"

        let defaults = UserDefaults.standard
        refreshLaunchAtLoginStatus()
        if let storedOpen = defaults.object(forKey: Self.openAngleKey) as? Double,
           let storedClosed = defaults.object(forKey: Self.closedAngleKey) as? Double,
           storedOpen - storedClosed >= Self.minimumCalibrationTravel
        {
            openAngle = storedOpen
            closedAngle = storedClosed
            calibrationMessage = "Используется сохранённая калибровка"
        }

        motionInterpolator.onFrame = { [weak self] angle in
            guard let self else { return }
            self.renderSensorAngle = angle
            // The control window is behind the login UI while locked. Keep
            // full-rate motion in the renderer without redrawing SwiftUI.
            if self.isUserSessionActive { self.sensorAngle = angle }
            self.updateOverlayVisibility()
            self.lockScreenOverlay?.refreshMotion()
        }

        sensor.onSample = { [weak self] angle, velocity in
            guard let self else { return }
            self.rawSensorAngle = angle
            let firstSample = !self.sensorHasSample
            if firstSample { self.sensorHasSample = true }

            // The sensor is polled at 60 Hz. Publishing every tiny velocity
            // decay invalidates the whole SwiftUI control rail while the lid
            // is stationary, which is especially expensive during Mission
            // Control. Keep full-rate updates during real motion, but publish
            // one exact zero once the sensor settles.
            let presentedVelocity = abs(velocity) < 0.35 ? 0 : velocity
            if abs(self.renderVelocity - presentedVelocity) > 0.15 {
                self.renderVelocity = presentedVelocity
                if self.isUserSessionActive { self.velocity = presentedVelocity }
            }

            self.lockScreenOverlay?.receive(angle: angle)
            let needsDesktopFrame = self.captureActivity.receive(
                angle: angle, velocity: velocity,
                at: ProcessInfo.processInfo.systemUptime,
                openAngle: self.openAngle)
            self.reconcileCaptureDemand(sensorRequestsCapture: needsDesktopFrame)
            if firstSample {
                // The pre-sleep angle is not a valid starting point after wake.
                self.motionInterpolator.snap(to: angle)
            } else {
                self.motionInterpolator.push(angle: angle)
            }
            self.updateOverlayVisibility()
        }

        sensor.onStatusChange = { [weak self] status in
            self?.sensorStatus = status
        }

        if sensor.isAvailable {
            sensor.start()
            sensorStatus = sensor.statusText
        }

        captureService.onStateChange = { [weak self] state in
            guard let self else { return }
            self.captureState = state

            if !state.isRunning, state != .starting {
                self.hasDesktopFrame = false
            }

            self.updateOverlayVisibility()
        }

        captureService.onFirstFrame = { [weak self] in
            self?.hasDesktopFrame = true
            self?.updateOverlayVisibility()
        }

        observeSystemLifecycle()
        lockScreenOverlay = LockScreenOverlayController(model: self)
        let requestedLockEffect = defaults.bool(forKey: Self.lockScreenEffectKey)
            || CommandLine.arguments.contains("--lock-screen-experiment")
            || CommandLine.arguments.contains("--lock-screen-smoke-test")
        setLockScreenEffectEnabled(requestedLockEffect, persist: false)
    }

    var isSensorAvailable: Bool {
        sensor.isAvailable
    }

    var sensorIndicatorText: String {
        if sensorHasSample { return "Датчик работает" }
        if sensor.isAvailable { return "Датчик найден" }
        return "Ручной режим"
    }

    var effectiveAngle: Double {
        source == .sensor && sensor.isAvailable ? sensorAngle : manualAngle
    }

    var effectiveVelocity: Double {
        source == .sensor && sensor.isAvailable ? velocity : 0
    }

    var foldParameters: FoldParameters {
        FoldMotionModel.parameters(
            angle: source == .sensor && sensor.isAvailable ? renderSensorAngle : manualAngle,
            velocity: source == .sensor && sensor.isAvailable ? renderVelocity : 0,
            openAngle: openAngle,
            closedAngle: closedAngle
        )
    }

    var sensorFoldParameters: FoldParameters {
        FoldMotionModel.parameters(angle: renderSensorAngle, velocity: renderVelocity,
                                   openAngle: openAngle, closedAngle: closedAngle)
    }

    var canCalibrate: Bool {
        source == .manual || sensorHasSample
    }

    var desktopFrameStore: DesktopFrameStore {
        captureService.frameStore
    }

    var effectTuningHasUnsavedChanges: Bool {
        effectTuning != savedEffectTuning
    }

    var canToggleFullscreenEffect: Bool {
        !isSystemSuspended
            && isUserSessionActive
            && displayEnvironment.supportsFullscreenEffect
            && wantsDesktopConnected
    }

    var fullscreenEffectStatusText: String {
        if let fullscreenEffectFailure { return fullscreenEffectFailure }
        if isSystemSuspended {
            return "Временно выключен на время сна — вернётся после пробуждения."
        }
        if !isUserSessionActive {
            return "Живой рабочий стол вернётся после разблокировки. Для экрана блокировки есть отдельный режим."
        }
        if !displayEnvironment.canCaptureBuiltInDisplay {
            return "Временно выключен: встроенный экран сейчас недоступен."
        }
        if displayEnvironment.isMirrored {
            return "Временно выключен при зеркалировании, чтобы внешний монитор остался без эффекта."
        }
        if !hasDesktopFrame {
            return captureState == .idle
                ? "Готов к движению крышки — захват начнётся при закрытии."
                : "Подключите рабочий стол для анимации складывания."
        }
        return "Живой экран складывается в перспективе; блюр усиливается от шарнира к краю."
    }

    var displayTopologyText: String {
        if isSystemSuspended {
            return "MacDuo ждёт пробуждения и затем заново подключит Built-in Retina Display."
        }
        if !isUserSessionActive {
            return "На экране пароля захват остановлен; после разблокировки он восстановится автоматически."
        }
        if !displayEnvironment.canCaptureBuiltInDisplay {
            return "Встроенный экран неактивен: эффект отключён, внешний монитор работает как обычно."
        }
        if displayEnvironment.isMirrored {
            return "Обнаружено зеркалирование: эффект отключён на обоих экранах до возврата расширенного режима."
        }
        return "При движении крышки захватывается только Built-in Retina Display. Внешний монитор остаётся обычным рабочим экраном."
    }

    func setEffectTuning(_ newValue: EffectTuning) {
        effectTuning = newValue.clamped()
        effectPresetMessage = effectTuningHasUnsavedChanges
            ? "Изменения применены, но не сохранены"
            : "Сохранённый пресет"
    }

    func saveEffectTuning() {
        let normalized = effectTuning.clamped()
        guard let data = try? JSONEncoder().encode(normalized) else {
            effectPresetMessage = "Не удалось сохранить пресет"
            return
        }

        UserDefaults.standard.set(data, forKey: Self.effectTuningKey)
        savedEffectTuning = normalized
        effectTuning = normalized
        effectPresetMessage = "Пресет сохранён"
    }

    func resetEffectTuning() {
        effectTuning = .standard
        effectPresetMessage = effectTuningHasUnsavedChanges
            ? "Возвращены базовые значения — сохраните их при необходимости"
            : "Базовый пресет"
    }

    func selectSource(_ newSource: MotionSource) {
        guard newSource != .sensor || sensor.isAvailable else {
            source = .manual
            updateOverlayVisibility()
            return
        }
        source = newSource
        if newSource == .sensor {
            motionInterpolator.snap(to: rawSensorAngle)
        }
        reconcileCaptureDemand(sensorRequestsCapture: captureActivity.wantsCapture)
        updateOverlayVisibility()
    }

    func calibrateOpenPoint() {
        let angle = calibrationAngle
        guard angle - closedAngle >= Self.minimumCalibrationTravel else {
            calibrationMessage = "Точка «открыто» должна быть выше финиша минимум на 20°"
            return
        }

        openAngle = roundedCalibrationAngle(angle)
        saveCalibration()
        calibrationMessage = "Открыто запомнено: " + formattedAngle(openAngle)
        updateOverlayVisibility()
    }

    func calibrateClosedPoint() {
        let angle = calibrationAngle
        guard openAngle - angle >= Self.minimumCalibrationTravel else {
            calibrationMessage = "Финиш должен быть ниже точки «открыто» минимум на 20°"
            return
        }

        closedAngle = roundedCalibrationAngle(angle)
        saveCalibration()
        calibrationMessage = "Финиш запомнен: " + formattedAngle(closedAngle)
        updateOverlayVisibility()
    }

    func resetCalibration() {
        openAngle = FoldMotionModel.defaultOpenAngle
        closedAngle = FoldMotionModel.defaultClosedAngle
        UserDefaults.standard.removeObject(forKey: Self.openAngleKey)
        UserDefaults.standard.removeObject(forKey: Self.closedAngleKey)
        calibrationMessage = "Возвращены исходные точки"
        updateOverlayVisibility()
    }

    func prepareOverlay() {
        guard overlayController == nil else { return }
        overlayController = OverlayController(model: self)
        if UserDefaults.standard.bool(forKey: Self.desktopEffectKey) {
            setFullscreenEffectEnabled(true, persist: false)
        }
        if UserDefaults.standard.bool(forKey: Self.desktopConnectionKey) {
            connectDesktop()
        }
        if CommandLine.arguments.contains("--fullscreen-effect") {
            setFullscreenEffectEnabled(true, persist: false)
        }
        updateOverlayVisibility()
        if CommandLine.arguments.contains("--perspective-check") {
            Task { @MainActor in
                do { try await PerspectiveChecks.run() }
                catch { print("✗ Perspective check: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--blur-coverage-check") {
            Task { @MainActor in
                do { try await BlurCoverageChecks.run() }
                catch { print("✗ Blur coverage check failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--duo-metal-fixture-check") {
            Task { @MainActor in
                do { try await MetalFoldFixtureChecks.run() }
                catch { print("✗ Metal fold fixture failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--duo-metal-live-check") {
            Task { @MainActor [weak self] in
                do {
                    guard let self else { return }
                    try await MetalFoldFixtureChecks.runLive(model: self)
                } catch { print("✗ Metal fold live check failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--blur-layer-diagnostic") {
            Task { @MainActor in
                do { try await BlurLayerDiagnostic.run() }
                catch { print("✗ Blur layer diagnostic failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--live-blur-smoke-test") {
            Task { @MainActor in
                do { try await OverlaySmokeChecks.runLiveBlur() }
                catch { print("✗ Live blur checks failed: \(error)") }
                NSApplication.shared.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--lock-screen-smoke-test") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                do {
                    try await OverlaySmokeChecks.run()
                } catch {
                    print("✗ Native overlay checks failed: \(error)")
                    NSApplication.shared.terminate(nil)
                    return
                }
                self?.previewLockScreenEffect()
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                self?.previewLockScreenEffect()
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func setLockScreenEffectEnabled(_ enabled: Bool, persist: Bool = true) {
        isLockScreenEffectEnabled = lockScreenOverlay?.setEnabled(enabled) ?? false
        if persist { UserDefaults.standard.set(isLockScreenEffectEnabled, forKey: Self.lockScreenEffectKey) }
    }

    func setLockScreenStatus(_ text: String) { lockScreenStatus = text }

    func previewLockScreenEffect() { lockScreenOverlay?.preview() }

    func connectDesktop() {
        if case .failed = captureState {
            // A completed recovery keeps its demand flag set. Explicit retry
            // must clear it so the next request can start a fresh stream.
            captureRequested = false
        }
        wantsDesktopConnected = true
        UserDefaults.standard.set(true, forKey: Self.desktopConnectionKey)
        refreshDisplayEnvironment()
        reconcileCaptureDemand(sensorRequestsCapture: captureActivity.wantsCapture)
    }

    var isDesktopEffectRequested: Bool {
        wantsDesktopConnected && isFullscreenEffectEnabled
    }

    func setDesktopEffectRequested(_ enabled: Bool) {
        if enabled {
            setFullscreenEffectEnabled(true)
            connectDesktop()
        } else {
            setFullscreenEffectEnabled(false)
            disconnectDesktop()
        }
    }

    func disconnectDesktop() {
        wantsDesktopConnected = false
        captureRequested = false
        UserDefaults.standard.set(false, forKey: Self.desktopConnectionKey)
        recoveryTask?.cancel()
        displayChangeTask?.cancel()
        updateOverlayVisibility()

        captureStopTask = Task {
            await captureService.stop()
        }
    }

    func requestScreenCapturePermission() {
        captureService.requestPermission()
    }

    func setFullscreenEffectEnabled(_ enabled: Bool, persist: Bool = true) {
        fullscreenEffectFailure = nil
        // Keep the requested state through lock/sleep and display changes;
        // updateOverlayVisibility decides whether a window may be shown now.
        isFullscreenEffectEnabled = enabled
        if persist { UserDefaults.standard.set(enabled, forKey: Self.desktopEffectKey) }
        updateOverlayVisibility()
    }

    func setFullscreenEffectFailure(_ message: String) {
        fullscreenEffectFailure = message
        isFullscreenEffectEnabled = false
        UserDefaults.standard.set(false, forKey: Self.desktopEffectKey)
        overlayMotionActive = false
        overlayController?.hide()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginNeedsApproval = false
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginMessage = "MacDuo запустится при следующем входе в macOS."
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginNeedsApproval = true
            launchAtLoginMessage = "Разрешите MacDuo в настройках объектов входа macOS."
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Включается только по вашему выбору."
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "macOS пока не видит объект входа. Попробуйте включить переключатель."
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Не удалось прочитать состояние запуска."
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginMessage = "Не удалось изменить запуск: \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func updateOverlayVisibility() {
        let canShow = isFullscreenEffectEnabled
            && hasDesktopFrame
            && (source == .manual || sensorHasSample)
            && !isSystemSuspended
            && isUserSessionActive
            && displayEnvironment.supportsFullscreenEffect

        guard canShow else {
            overlayMotionActive = false
            overlayController?.hide()
            return
        }

        let parameters = foldParameters
        if overlayMotionActive {
            overlayMotionActive = FoldMotionModel.shouldKeepOverlayVisible(for: parameters)
        } else {
            overlayMotionActive = FoldMotionModel.shouldPresentOverlay(for: parameters)
        }

        overlayController?.setVisible(overlayMotionActive)
    }

    private func reconcileCaptureDemand(sensorRequestsCapture: Bool) {
        guard wantsDesktopConnected, !isSystemSuspended, isUserSessionActive,
              displayEnvironment.supportsFullscreenEffect else { return }

        let needsFrame = source == .manual || sensorRequestsCapture
        if needsFrame {
            if !captureRequested {
                scheduleCaptureRecovery(initialDelayNanoseconds: 0)
            }
        } else if captureRequested {
            captureRequested = false
            recoveryTask?.cancel()
            captureStopTask = Task { await captureService.stop() }
        }
    }

    private func observeSystemLifecycle() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.overlayController?.close() }
            .store(in: &lifecycleCancellables)

        // Workspace session notifications describe session switching; actual
        // screen lock/unlock also needs the distributed notifications.
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleSessionDidResignActive() }
            .store(in: &lifecycleCancellables)
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSessionDidBecomeActive()
                self?.scheduleSensorRecovery()
            }
            .store(in: &lifecycleCancellables)

        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleWillSleep()
            }
            .store(in: &lifecycleCancellables)

        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDidWake()
            }
            .store(in: &lifecycleCancellables)

        workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.sensorHasSample else { return }
                self.isSystemSuspended = false
                self.scheduleSensorRecovery()
            }
            .store(in: &lifecycleCancellables)

        workspaceCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSessionDidBecomeActive()
            }
            .store(in: &lifecycleCancellables)

        workspaceCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSessionDidResignActive()
            }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleScreenParametersChanged()
            }
            .store(in: &lifecycleCancellables)
    }

    private func handleWillSleep() {
        isSystemSuspended = true
        captureRequested = false
        captureActivity.reset()
        recoveryTask?.cancel()
        displayChangeTask?.cancel()
        sensorRecoveryTask?.cancel()
        if sensor.isAvailable {
            sensor.suspendForSleep()
        }
        sensorHasSample = false
        velocity = 0
        renderVelocity = 0
        hasDesktopFrame = false
        overlayMotionActive = false
        overlayController?.hide()

        guard wantsDesktopConnected else { return }
        captureStopTask = Task {
            await captureService.stop()
        }
    }

    private func handleDidWake() {
        isSystemSuspended = false
        refreshDisplayEnvironment()
        scheduleSensorRecovery()
        guard wantsDesktopConnected else { return }

        // macOS rebuilds the display graph for a short moment after wake.
        // Restarting the stream against the old graph can produce a black frame.
        scheduleCaptureRecovery(
            initialDelayNanoseconds: 700_000_000,
            restartBeforeStarting: true
        )
    }

    private func handleSessionDidBecomeActive() {
        isUserSessionActive = true
        sensorAngle = renderSensorAngle
        velocity = renderVelocity
        refreshDisplayEnvironment()
        guard wantsDesktopConnected, !isSystemSuspended else { return }
        scheduleCaptureRecovery(
            initialDelayNanoseconds: 350_000_000,
            restartBeforeStarting: true
        )
    }

    private func handleSessionDidResignActive() {
        isUserSessionActive = false
        captureRequested = false
        captureActivity.reset()
        recoveryTask?.cancel()
        displayChangeTask?.cancel()
        hasDesktopFrame = false
        overlayMotionActive = false
        overlayController?.hide()

        guard wantsDesktopConnected else { return }
        captureStopTask = Task {
            await captureService.stop()
        }
    }

    private func handleScreenParametersChanged() {
        let previousEnvironment = displayEnvironment
        refreshDisplayEnvironment()
        // A clamshell transition can post the same screen configuration more
        // than once. Restarting capture on each notification hides the first
        // recovered frame and brings back the 650 ms opening delay.
        guard displayEnvironment != previousEnvironment else { return }

        if previousEnvironment.supportsFullscreenEffect,
           displayEnvironment.supportsFullscreenEffect,
           previousEnvironment.builtInDisplayID == displayEnvironment.builtInDisplayID,
           previousEnvironment.geometry?.pixelWidth == displayEnvironment.geometry?.pixelWidth,
           previousEnvironment.geometry?.pixelHeight == displayEnvironment.geometry?.pixelHeight
        {
            // Moving the built-in display within a multi-monitor layout only
            // changes the overlay window's position. The stream is still the
            // same size and need not lose its first frame on reopening.
            updateOverlayVisibility()
            return
        }

        overlayMotionActive = false
        overlayController?.hide()

        recoveryTask?.cancel()
        displayChangeTask?.cancel()
        guard wantsDesktopConnected, !isSystemSuspended, isUserSessionActive else { return }

        if !displayEnvironment.supportsFullscreenEffect {
            // Closing the lid removes the built-in display from the active
            // topology. Release its stream now instead of waiting for the
            // stream delegate to notice that its source disappeared.
            displayChangeTask = Task { @MainActor [weak self] in
                await self?.captureService.stop()
            }
            return
        }

        if !previousEnvironment.supportsFullscreenEffect {
            // In clamshell mode the external display keeps the user session
            // active. On reopening, a 650 ms debounce used to start capture
            // after macOS had already moved windows back to the MacBook.
            // Try immediately; scheduleCaptureRecovery still retries if the
            // rebuilt display is not shareable on its first notification.
            scheduleCaptureRecovery(initialDelayNanoseconds: 0,
                                    restartBeforeStarting: true)
            return
        }

        displayChangeTask = Task { @MainActor [weak self] in
            // Hot-plug and wake usually send several notifications while
            // macOS is still rebuilding the display graph. Debounce them into
            // one clean restart instead of briefly capturing an old surface.
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard let self, !Task.isCancelled else { return }
            self.refreshDisplayEnvironment()

            if !self.displayEnvironment.supportsFullscreenEffect {
                await self.captureService.stop()
                return
            }

            self.scheduleCaptureRecovery(
                initialDelayNanoseconds: 0,
                restartBeforeStarting: true
            )
        }
    }

    private func refreshDisplayEnvironment() {
        displayEnvironment = DesktopCaptureService.currentDisplayEnvironment()
    }

    private func scheduleSensorRecovery() {
        guard !sensorHasSample else { return }
        sensorRecoveryTask?.cancel()

        sensorRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // First attempt immediately; only failed attempts need a backoff.
            for delay: UInt64 in [0, 50_000_000, 100_000_000, 250_000_000, 500_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, !self.isSystemSuspended else { return }
                if self.sensorHasSample { return }
                if self.sensor.resumeAfterSleep() {
                    return
                }
            }
        }
    }

    private func scheduleCaptureRecovery(
        initialDelayNanoseconds: UInt64,
        restartBeforeStarting: Bool = false
    ) {
        captureRequested = true
        captureActivity.forceCapture()
        recoveryTask?.cancel()

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let captureStopTask = self.captureStopTask {
                await captureStopTask.value
            }
            if initialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            }

            guard !Task.isCancelled, self.captureRequested else { return }

            if restartBeforeStarting {
                await self.captureService.stop()
                guard !Task.isCancelled else { return }
            }

            for attempt in 0 ..< 3 {
                guard self.wantsDesktopConnected,
                      self.captureRequested,
                      !self.isSystemSuspended,
                      self.isUserSessionActive,
                      !Task.isCancelled
                else { return }
                self.refreshDisplayEnvironment()

                guard self.displayEnvironment.supportsFullscreenEffect else {
                    await self.captureService.stop()
                    return
                }

                if self.captureState.isRunning {
                    return
                }

                await self.captureService.start()
                guard !Task.isCancelled else { return }
                if self.captureState.isRunning {
                    return
                }

                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }
    }

    private var calibrationAngle: Double {
        source == .sensor && sensorHasSample ? rawSensorAngle : manualAngle
    }

    private func roundedCalibrationAngle(_ angle: Double) -> Double {
        (angle * 2).rounded() / 2
    }

    private func formattedAngle(_ angle: Double) -> String {
        String(format: "%.1f°", angle)
    }

    private func saveCalibration() {
        UserDefaults.standard.set(openAngle, forKey: Self.openAngleKey)
        UserDefaults.standard.set(closedAngle, forKey: Self.closedAngleKey)
    }

    private static func loadEffectTuning() -> EffectTuning {
        guard let data = UserDefaults.standard.data(forKey: effectTuningKey),
              let decoded = try? JSONDecoder().decode(EffectTuning.self, from: data)
        else {
            return .standard
        }

        return decoded.clamped()
    }
}
