import CoreVideo
import Foundation

/// A single retained ScreenCaptureKit frame shared by the capture queue and
/// the small preview. Consumers pull the newest frame at display cadence;
/// intermediate capture frames may be skipped without creating latency.
final class DesktopFrameStore: @unchecked Sendable {
    struct Snapshot {
        let pixelBuffer: CVPixelBuffer
        let generation: UInt64
    }

    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?
    private var generation: UInt64 = 0

    func update(_ nextPixelBuffer: CVPixelBuffer) {
        lock.lock()
        pixelBuffer = nextPixelBuffer
        generation &+= 1
        lock.unlock()
    }

    func snapshot() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let pixelBuffer else { return nil }
        return Snapshot(pixelBuffer: pixelBuffer, generation: generation)
    }

    func clear() {
        lock.lock()
        pixelBuffer = nil
        generation &+= 1
        lock.unlock()
    }

}
