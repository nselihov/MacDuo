import Foundation

/// Do not introduce an opening animation after the user already saw a sharp
/// lock screen. After a missed wake deadline, a new closing gesture re-arms it.
public struct WakeMotionGate {
    public static let sampleDeadline = 0.4
    private var deadline: Double?
    private var suppressOpening = false
    private var highestAngle: Double?

    public init() {}

    public mutating func begin(at time: Double) {
        deadline = time + Self.sampleDeadline
        suppressOpening = false
        highestAngle = nil
    }

    /// Once a visible lock-screen pass has been retired, do not start it
    /// again while the lid continues opening. A real closing movement re-arms it.
    public mutating func suppressUntilClosing(from angle: Double) {
        guard angle.isFinite else { return }
        deadline = nil
        suppressOpening = true
        highestAngle = max(highestAngle ?? angle, angle)
    }

    public mutating func receive(angle: Double, at time: Double, openAngle: Double) {
        guard angle.isFinite, time.isFinite else { return }
        if let deadline {
            suppressOpening = time > deadline
            self.deadline = nil
        }
        guard suppressOpening else { return }
        highestAngle = max(highestAngle ?? angle, angle)
        if angle >= openAngle - 2 || angle <= highestAngle! - 2 {
            suppressOpening = false
            highestAngle = nil
        }
    }

    public mutating func allowsMotion(at time: Double) -> Bool {
        if let deadline {
            if time <= deadline { return false }
            self.deadline = nil
            suppressOpening = true
        }
        return !suppressOpening
    }
}
