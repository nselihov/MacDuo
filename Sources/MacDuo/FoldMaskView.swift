import AppKit
import MacDuoCore
import QuartzCore

/// A broad translucent top edge lets the physical screen darken as the lid
/// closes. Its full-width ramp has no side cutout over the anchored image.
@MainActor
final class FoldMaskView: NSView {
    private let maskGroup = CALayer()
    private let topDissolve = CAGradientLayer()
    private let upperFill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(maskGroup)
        // The wide alpha ramp darkens the whole screen width without forming
        // a hard side boundary against the anchored image.
        topDissolve.startPoint = CGPoint(x: 0.5, y: 0)
        topDissolve.endPoint = CGPoint(x: 0.5, y: 1)
        let stops = (0...32).map { Double($0) / 32 }
        topDissolve.locations = stops.map { NSNumber(value: $0) }
        topDissolve.colors = stops.map { t in
            // Zero slope and curvature at both ends; no stripe where the
            // gradient meets the clear interior or the solid black exterior.
            let alpha = t * t * t * (t * (t * 6 - 15) + 10)
            return NSColor.black.withAlphaComponent(alpha).cgColor
        }
        maskGroup.addSublayer(topDissolve)
        upperFill.backgroundColor = NSColor.black.cgColor
        maskGroup.addSublayer(upperFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(progress: Double, tuning: EffectTuning) {
        let progress = min(max(progress, 0), 1)
        let tuning = tuning.clamped()
        let points = FoldGlassGeometry.corners(progress: progress, tuning: tuning)
        let bottomY = CGFloat(points[0].y) * bounds.height
        let topY = CGFloat(points[2].y) * bounds.height
        let growth = pow(progress, 0.8)
        let inward = CGFloat((0.012 + 0.20 * growth) * tuning.edgeDissolve) * bounds.height
        let outward = CGFloat((0.006 + 0.07 * growth) * tuning.edgeDissolve) * bounds.height
        let fadeStart = max(topY - inward, bottomY + (topY - bottomY) * 0.15)
        let fadeEnd = topY + outward

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskGroup.frame = bounds
        topDissolve.frame = CGRect(x: bounds.minX, y: fadeStart,
                                   width: bounds.width, height: fadeEnd - fadeStart)
        // Overlap the nearly opaque tail by one point to prevent a subpixel
        // gap between independently rasterized layers at fractional lid angles.
        upperFill.frame = CGRect(x: bounds.minX, y: fadeEnd - 1,
                                 width: bounds.width, height: max(bounds.maxY - fadeEnd + 1, 0))
        // A fully open glass must leave no shadow or colored frame behind.
        let t = min(max(progress / 0.035, 0), 1)
        maskGroup.opacity = Float(t * t * (3 - 2 * t))
        CATransaction.commit()
    }
}
