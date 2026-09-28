import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
final class DesktopCaptureService {
    struct DisplayEnvironment: Equatable, Sendable {
        struct Geometry: Equatable, Sendable {
            let pixelWidth: Int
            let pixelHeight: Int
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        let builtInDisplayID: CGDirectDisplayID?
        let isActive: Bool
        let isMirrored: Bool
        let geometry: Geometry?

        var canCaptureBuiltInDisplay: Bool {
            builtInDisplayID != nil && isActive
        }

        var supportsFullscreenEffect: Bool {
            canCaptureBuiltInDisplay && !isMirrored
        }
    }

    enum State: Equatable {
        case idle
        case permissionRequired
        case starting
        case running(displayName: String)
        case restartRequired
        case failed(message: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    var onStateChange: ((State) -> Void)?
    var onFirstFrame: (() -> Void)?

    private(set) var state: State
    private var stream: SCStream?
    private var output: DesktopStreamOutput?
    private var operationGeneration: UInt64 = 0
    private var startInProgress = false
    nonisolated let frameStore = DesktopFrameStore()
    private let captureQueue = DispatchQueue(label: "com.nikolay.macduo.capture", qos: .userInteractive)

    init() {
        state = CGPreflightScreenCaptureAccess() ? .idle : .permissionRequired
    }

    func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        setState(granted ? .restartRequired : .permissionRequired)
    }

    func start() async {
        guard stream == nil, !startInProgress else { return }
        guard CGPreflightScreenCaptureAccess() else {
            setState(.permissionRequired)
            return
        }

        startInProgress = true
        operationGeneration &+= 1
        let generation = operationGeneration
        defer { startInProgress = false }
        setState(.starting)

        do {
            let displayID = try Self.builtInDisplayID()
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.builtInDisplayUnavailable
            }

            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = shareableContent.applications.filter {
                $0.bundleIdentifier == ownBundleIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )

            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let output = DesktopStreamOutput(
                frameStore: frameStore,
                onFirstFrame: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.operationGeneration == generation else { return }
                        self.onFirstFrame?()
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.operationGeneration == generation else { return }
                        self.stream = nil
                        self.output = nil
                        self.setState(.failed(message: error.localizedDescription))
                    }
                }
            )

            let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)

            guard generation == operationGeneration else { return }
            self.output = output
            self.stream = stream
            try await stream.startCapture()

            guard generation == operationGeneration, self.stream === stream else {
                try? await stream.stopCapture()
                return
            }
            setState(.running(displayName: Self.builtInDisplayName()))
        } catch {
            guard generation == operationGeneration else { return }
            stream = nil
            output = nil
            setState(.failed(message: error.localizedDescription))
        }
    }

    func stop() async {
        operationGeneration &+= 1
        let generation = operationGeneration
        let activeStream = stream
        stream = nil
        output = nil
        frameStore.clear()

        if let activeStream {
            try? await activeStream.stopCapture()
        }

        guard generation == operationGeneration else { return }
        setState(CGPreflightScreenCaptureAccess() ? .idle : .permissionRequired)
    }

    static func currentDisplayEnvironment() -> DisplayEnvironment {
        guard let displays = onlineDisplayIDs(),
              let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 })
        else {
            return DisplayEnvironment(
                builtInDisplayID: nil,
                isActive: false,
                isMirrored: false,
                geometry: nil
            )
        }

        let bounds = CGDisplayBounds(builtIn)
        return DisplayEnvironment(
            builtInDisplayID: builtIn,
            isActive: CGDisplayIsActive(builtIn) != 0,
            isMirrored: CGDisplayIsInMirrorSet(builtIn) != 0,
            geometry: DisplayEnvironment.Geometry(
                pixelWidth: CGDisplayPixelsWide(builtIn),
                pixelHeight: CGDisplayPixelsHigh(builtIn),
                x: Double(bounds.origin.x),
                y: Double(bounds.origin.y),
                width: Double(bounds.width),
                height: Double(bounds.height)
            )
        )
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    private static func builtInDisplayID() throws -> CGDirectDisplayID {
        guard let displays = onlineDisplayIDs() else {
            throw CaptureError.cannotReadDisplays
        }

        guard let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }),
              CGDisplayIsActive(builtIn) != 0
        else {
            throw CaptureError.builtInDisplayUnavailable
        }

        return builtIn
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID]? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else { return nil }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else { return nil }
        return Array(displays.prefix(Int(displayCount)))
    }

    private static func builtInDisplayName() -> String {
        NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        })?.localizedName ?? "Встроенный дисплей"
    }
}

private enum CaptureError: LocalizedError {
    case cannotReadDisplays
    case builtInDisplayUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotReadDisplays:
            "Не удалось прочитать список дисплеев."
        case .builtInDisplayUnavailable:
            "Встроенный дисплей MacBook не найден."
        }
    }
}

private final class DesktopStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let frameStore: DesktopFrameStore
    private let onFirstFrame: @Sendable () -> Void
    private let onFailure: @Sendable (Error) -> Void
    private var deliveredFirstFrame = false

    init(
        frameStore: DesktopFrameStore,
        onFirstFrame: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.frameStore = frameStore
        self.onFirstFrame = onFirstFrame
        self.onFailure = onFailure
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer
        else { return }

        frameStore.update(imageBuffer)
        if !deliveredFirstFrame {
            deliveredFirstFrame = true
            onFirstFrame()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error)
    }
}
