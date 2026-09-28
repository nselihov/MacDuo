import AppKit
import MacDuoCore
import QuartzCore

/// Blur grows away from the hinge, while both projected layers fade before
/// their finite image reaches the outer screen boundary.
@MainActor
enum BlurRevealMask {
    static func makeTopShadow() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.colors = [0.0, 0.0, 1.0, 1.0].map {
            NSColor.black.withAlphaComponent($0).cgColor
        }
        return layer
    }

    static func updateTopShadow(_ layer: CAGradientLayer, bounds: CGRect,
                                progress: Double, tuning: EffectTuning) {
        let p = min(max(progress, 0), 1)
        let top = FoldGlassGeometry.project(.init(x: 0.5, y: 1),
                                            progress: p, tuning: tuning).y
        let spread = min((0.10 + 0.18 * pow(p, 0.8)) * tuning.clamped().edgeDissolve,
                         top * 0.65)
        let start = max(0, top - spread)
        let end = min(1, max(start + 0.001, top - 0.025))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.locations = [0, start, end, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
    }

    static func make() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        let rise = (0...16).map { smooth(Double($0) / 16) }
        let fall = (0...8).map { 1 - smooth(Double($0) / 8) }
        layer.colors = ([0.0] + rise + [1.0] + fall + [0.0])
            .map { NSColor.black.withAlphaComponent($0).cgColor }
        return layer
    }

    static func makeSideFeather() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        let rise = (0...8).map { smooth(Double($0) / 8) }
        let fall = (0...8).map { 1 - smooth(Double($0) / 8) }
        layer.colors = ([0.0] + rise + [1.0] + fall + [0.0])
            .map { NSColor.black.withAlphaComponent($0).cgColor }
        var locations: [Double] = [0]
        locations += (0...8).map { 0.12 * Double($0) / 8 }
        locations.append(0.5)
        locations += (0...8).map { 0.88 + 0.12 * Double($0) / 8 }
        locations.append(1)
        layer.locations = locations.map { NSNumber(value: $0) }
        return layer
    }

    static func update(_ layer: CAGradientLayer, bounds: CGRect, progress: Double, tuning: EffectTuning) {
        let p = min(max(progress, 0), 1)
        let top = FoldGlassGeometry.project(.init(x: 0.5, y: 1), progress: p, tuning: tuning).y
        let fadeEnd = min(max(top - 0.01, 0.02), 0.98)
        let fadeStart = max(top * 0.78, fadeEnd - 0.12 * tuning.clamped().edgeDissolve)
        let riseStart = top * 0.25
        let riseEnd = top * 0.72
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        var locations: [Double] = [0]
        locations += (0...16).map { riseStart + (riseEnd - riseStart) * Double($0) / 16 }
        locations.append(fadeStart)
        locations += (0...8).map { fadeStart + (fadeEnd - fadeStart) * Double($0) / 8 }
        locations.append(1)
        layer.locations = locations.map { NSNumber(value: $0) }
        CATransaction.commit()
    }

    static func updateSideFeather(_ layer: CAGradientLayer, bounds: CGRect, progress: Double) {
        let edge = 0.08 + 0.18 * min(max(progress, 0), 1)
        var locations: [Double] = [0]
        locations += (0...8).map { edge * Double($0) / 8 }
        locations.append(0.5)
        locations += (0...8).map { 1 - edge + edge * Double($0) / 8 }
        locations.append(1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.locations = locations.map { NSNumber(value: $0) }
        CATransaction.commit()
    }

    private static func smooth(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }
}
