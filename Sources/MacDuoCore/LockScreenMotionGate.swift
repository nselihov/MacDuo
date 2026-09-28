import Foundation

/// Controls lifetime only. A paused lid keeps its current frame while the
/// sensor is alive; all optical parameters still come from FoldMotionModel.
public struct LockScreenMotionGate {
    public static let sampleLifetime = 0.3
    public static let idleTimeout = 2.0
    public static let movementThreshold = 1.5
    private var sampleTime: Double?
    private var motionTime: Double?
    private var motionAnchor: Double?
    private var active = false

    public init() {}

    public mutating func receive(angle: Double, at time: Double) {
        guard angle.isFinite, time.isFinite else { return }
        sampleTime = time
        // Accumulate slow movement, but do not renew the lifetime for sensor noise.
        // HID reports whole degrees; +/- one degree can just be quantization.
        if motionAnchor == nil || abs(angle - motionAnchor!) >= Self.movementThreshold {
            motionAnchor = angle
            motionTime = time
        }
    }

    public mutating func shouldShow(parameters: FoldParameters, at time: Double) -> Bool {
        guard time.isFinite, let sampleTime, let motionTime,
              time >= sampleTime, time - sampleTime <= Self.sampleLifetime,
              time >= motionTime,
              (active || time - motionTime < Self.idleTimeout) else {
            active = false
            return false
        }
        active = active
            ? FoldMotionModel.shouldKeepOverlayVisible(for: parameters)
            : FoldMotionModel.shouldPresentOverlay(for: parameters)
        return active
    }

    public mutating func invalidate() { self = Self() }
}

/// Completes an opening from the raw HID angle, before interpolation can
/// leave a blurred login screen at the top of the travel.
/// A wider return threshold prevents whole-degree sensor jitter from replaying
/// the effect while the lid is nearly open.
public struct LockScreenOpenStop {
    public static let finishBeforeOpenDegrees = 5.0
    public static let restartBelowOpenDegrees = 9.0
    public private(set) var allowsPresentation = true

    public init() {}

    @discardableResult
    public mutating func receive(angle: Double, openAngle: Double) -> Bool {
        guard angle.isFinite, openAngle.isFinite else { return allowsPresentation }
        if angle >= openAngle - Self.finishBeforeOpenDegrees {
            allowsPresentation = false
        } else if angle <= openAngle - Self.restartBelowOpenDegrees {
            allowsPresentation = true
        }
        return allowsPresentation
    }
}
