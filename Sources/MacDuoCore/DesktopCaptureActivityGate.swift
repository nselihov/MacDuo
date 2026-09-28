import Foundation

/// Keeps the live desktop stream only while the lid is moving or folded.
/// A short open-position hold lets the last animation finish before capture stops.
public struct DesktopCaptureActivityGate {
    public static let openHoldSeconds = 1.5

    public private(set) var wantsCapture = false
    private var openSince: TimeInterval?
    private var restingAngle: Double?

    public init() {}

    public mutating func forceCapture() {
        wantsCapture = true
        openSince = nil
        restingAngle = nil
    }

    public mutating func reset() {
        wantsCapture = false
        openSince = nil
        restingAngle = nil
    }

    @discardableResult
    public mutating func receive(
        angle: Double,
        velocity: Double,
        at time: TimeInterval,
        openAngle: Double
    ) -> Bool {
        guard angle.isFinite, velocity.isFinite, time.isFinite, openAngle.isFinite else {
            return wantsCapture
        }

        if wantsCapture {
            if angle >= openAngle - 0.5 && abs(velocity) < 0.8 {
                if openSince == nil { openSince = time }
                if time - openSince! >= Self.openHoldSeconds {
                    wantsCapture = false
                    restingAngle = angle
                    openSince = nil
                }
            } else {
                openSince = nil
            }
        } else {
            restingAngle = max(restingAngle ?? angle, angle)
            let movedFromRest = angle <= (restingAngle ?? angle) - 1.0 && velocity < -4
            // Start before FoldMotionModel's visible dead zone ends. A frame
            // can then arrive while the real screen is still unobstructed.
            if angle < openAngle - 1.0 || movedFromRest {
                wantsCapture = true
                openSince = nil
                restingAngle = nil
            }
        }

        return wantsCapture
    }
}
