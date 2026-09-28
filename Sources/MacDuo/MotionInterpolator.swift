import Foundation
import QuartzCore

@MainActor
final class MotionInterpolator {
    var onFrame: ((Double) -> Void)?

    private var targetAngle: Double?
    private var presentedAngle: Double?
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval?

    func push(angle: Double) {
        guard let currentTarget = targetAngle, let presentedAngle else {
            targetAngle = angle
            self.presentedAngle = angle
            onFrame?(angle)
            return
        }

        targetAngle = angle
        guard abs(angle - currentTarget) > 0.0001 || abs(angle - presentedAngle) > 0.002 else {
            return
        }

        startTimerIfNeeded()
    }

    func snap(to angle: Double) {
        timer?.invalidate()
        timer = nil
        lastTimestamp = nil
        targetAngle = angle
        presentedAngle = angle
        onFrame?(angle)
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        lastTimestamp = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let targetAngle, let presentedAngle else { return }

        let now = CACurrentMediaTime()
        let elapsed = min(max(now - (lastTimestamp ?? now), 1.0 / 240.0), 1.0 / 20.0)
        lastTimestamp = now

        let response = 1 - exp(-elapsed * 34)
        let nextAngle = presentedAngle + (targetAngle - presentedAngle) * response

        if abs(targetAngle - nextAngle) < 0.002 {
            self.presentedAngle = targetAngle
            onFrame?(targetAngle)
            timer?.invalidate()
            timer = nil
            lastTimestamp = nil
        } else {
            self.presentedAngle = nextAngle
            onFrame?(nextAngle)
        }
    }
}
