import Foundation

/// Canonical projection of the screen plane and its soft surround.
public enum FoldGlassGeometry {
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// Unit coordinates, origin at the bottom left; the hinge stays at y = 0.
    public static func project(_ point: Point, progress: Double, tuning: EffectTuning) -> Point {
        let p = min(max(progress, 0), 1)
        let eye = 3.1 / tuning.clamped().perspectiveDepth
        let bend = p * 1.36135682
        let scale = eye / max(eye + point.y * sin(bend), 0.25)
        return Point(x: 0.5 + (point.x - 0.5) * scale,
                     y: 0.5 + (point.y * cos(bend) - 0.5) * scale)
    }

    /// Inverse sampling coordinates for a live backdrop displacement map.
    public static func unproject(_ point: Point, progress: Double, tuning: EffectTuning) -> Point {
        let p = min(max(progress, 0), 1)
        let eye = 3.1 / tuning.clamped().perspectiveDepth
        let bend = p * 1.36135682
        let y = eye * point.y / max(eye * cos(bend) - (point.y - 0.5) * sin(bend), 0.001)
        return Point(x: 0.5 + (point.x - 0.5) * (eye + y * sin(bend)) / eye, y: y)
    }

    public static func corners(progress: Double, tuning: EffectTuning) -> [Point] {
        let p = min(max(progress, 0), 1)
        let tuning = tuning.clamped()
        let overscan = (0.018 + p * 0.145) * tuning.edgeDissolve
        return [Point(x: -overscan, y: -overscan), Point(x: 1 + overscan, y: -overscan),
                Point(x: 1 + overscan, y: 1 + overscan), Point(x: -overscan, y: 1 + overscan)]
            .map { project($0, progress: p, tuning: tuning) }
    }
}
