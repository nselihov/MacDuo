import Foundation

/// Releases our own overlay if the main thread stops renewing it. A separate
/// queue calls WindowServer directly, without waiting on AppKit's main thread.
/// Dispatch uptime pauses during system sleep, preserving the prepared layer.
public final class SkyLightWindowLease: @unchecked Sendable {
    private let owner: SkyLightBridge // Keep dlopen symbols alive until cancellation.
    private let connection: Int32
    private let windowID: UInt32
    private let setAlpha: @convention(c) (Int32, UInt32, Float) -> Int32
    private let lock = NSLock()
    private var lastRenewal = DispatchTime.now().uptimeNanoseconds
    private var active = true
    private var expired = false
    private var releaseResult: Int32?
    private var timer: DispatchSourceTimer?

    init(owner: SkyLightBridge, connection: Int32, windowID: UInt32,
         setAlpha: @escaping @convention(c) (Int32, UInt32, Float) -> Int32) {
        self.owner = owner
        self.connection = connection
        self.windowID = windowID
        self.setAlpha = setAlpha
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "MacDuo.overlay-lease"))
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
    }

    public func renew(alpha: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        lastRenewal = DispatchTime.now().uptimeNanoseconds
        if expired {
            _ = setAlpha(connection, windowID, Float(alpha))
            expired = false
        }
    }

    public var didReleaseWindow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expired && releaseResult == 0
    }

    public func cancel() {
        lock.lock()
        active = false
        lock.unlock()
        timer?.cancel()
        timer = nil
    }

    private func check() {
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        guard active, !expired, now >= lastRenewal,
              now - lastRenewal > 2_500_000_000 else { return }
        releaseResult = setAlpha(connection, windowID, 0)
        expired = releaseResult == 0
    }

    deinit { timer?.cancel() }
}
