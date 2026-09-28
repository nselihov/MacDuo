import AppKit
import MacDuoCore
import MacDuoSkyLight

/// A full-frame inverse mesh changes sampling coordinates without shrinking
/// the backdrop's capture region.
@MainActor
enum FoldProjectionMesh {
    /// Keeps the live image near its original screen coordinates while the
    /// glass boundary still follows the lid. This is the local equivalent of
    /// projecting a folded panel back onto the flat display plane.
    static func sample(_ destination: FoldGlassGeometry.Point, progress: Double,
                       tuning: EffectTuning) -> FoldGlassGeometry.Point {
        let from = FoldGlassGeometry.unproject(destination, progress: progress, tuning: tuning)
        let p = min(max(progress, 0), 1)
        let anchor = 0.4 + 0.3 * p
        return .init(x: from.x * (1 - anchor) + destination.x * anchor,
                     y: from.y * (1 - anchor) + destination.y * anchor)
    }

    static func displayPoint(for source: FoldGlassGeometry.Point, progress: Double,
                             tuning: EffectTuning) -> FoldGlassGeometry.Point {
        let top = FoldGlassGeometry.project(.init(x: 0.5, y: 1),
                                            progress: progress, tuning: tuning).y
        var lower = 0.0, upper = top
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            if sample(.init(x: 0.5, y: middle), progress: progress, tuning: tuning).y < source.y {
                lower = middle
            } else {
                upper = middle
            }
        }
        let y = (lower + upper) / 2
        let p = min(max(progress, 0), 1)
        let anchor = 0.4 + 0.3 * p
        let eye = 3.1 / tuning.clamped().perspectiveDepth
        let physicalY = FoldGlassGeometry.unproject(.init(x: 0.5, y: y),
                                                    progress: progress, tuning: tuning).y
        let scale = (eye + physicalY * sin(p * 1.36135682)) / eye
        let x = 0.5 + (source.x - 0.5) / (anchor + (1 - anchor) * scale)
        return .init(x: x, y: y)
    }

    static func make(progress: Double, tuning: EffectTuning) -> NSObject? {
        let divisions = 40
        let points = (0...divisions).flatMap { row in
            (0...divisions).map { col -> BackdropMesh.Point in
                let destination = CGPoint(x: Double(col) / Double(divisions), y: Double(row) / Double(divisions))
                let from = sample(.init(x: destination.x, y: destination.y),
                                  progress: progress, tuning: tuning)
                // Repeated edge texels extend into the accepted dissolve. Keep
                // a tiny UV slope so the compositor never drops a degenerate face.
                let source = CGPoint(x: min(max(from.x, 0), 1) * 0.9998 + destination.x * 0.0002,
                                     y: min(max(from.y, 0), 1) * 0.9998 + destination.y * 0.0002)
                return BackdropMesh.Point(source: source, destination: destination)
            }
        }
        return BackdropMesh.make(columns: divisions, rows: divisions, points: points)
    }
}
