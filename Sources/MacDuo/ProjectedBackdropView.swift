import AppKit
import MacDuoCore
import MacDuoSkyLight
import QuartzCore

@MainActor
final class ProjectedBackdropView: NSView {
    private let backdrop: SystemBackdrop
    private let edgeBackdrop: SystemBackdrop
    private let projectionGroup = CALayer()
    private let projectedContainer = CALayer()
    private let verticalContainer = CALayer()
    private let revealMask = BlurRevealMask.make()
    private let sideFeather = BlurRevealMask.makeSideFeather()
    private let validityMask = ProjectionValidityMask.makeLayer()
    private let sideShadow = CALayer()
    private let sideShadowMask = ProjectionValidityMask.makeLayer()
    private let topShadow = BlurRevealMask.makeTopShadow()
    private var lastProgress = -1.0
    private var lastDepth = -1.0
    private var lastEdgeDissolve = -1.0
    private var lastMaskProgress = -1.0
    private var lastMaskDepth = -1.0
    private var requestedRadius = 1.0
    private var lastBaseRadius = -1
    private var lastProjectedRadius = -1

    init(frame: NSRect, backdrop: SystemBackdrop) throws {
        self.backdrop = backdrop
        edgeBackdrop = try SystemBackdrop()
        super.init(frame: frame)
        wantsLayer = true
        // The base layer carries the entire live image through the fold.
        // The stronger layer fades in away from the hinge.
        layer?.addSublayer(projectionGroup)
        projectionGroup.addSublayer(edgeBackdrop.layer)
        projectionGroup.addSublayer(projectedContainer)
        sideShadow.backgroundColor = NSColor.black.cgColor
        sideShadow.mask = sideShadowMask
        layer?.addSublayer(sideShadow)
        layer?.addSublayer(topShadow)
        projectedContainer.addSublayer(verticalContainer)
        verticalContainer.addSublayer(backdrop.layer)
        projectionGroup.mask = validityMask
        projectedContainer.mask = sideFeather
        verticalContainer.mask = revealMask
        guard FoldProjectionMesh.make(progress: 0, tuning: .standard) != nil else {
            throw SkyLightBridge.Failure.unavailable("CAMutableMeshTransform")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sideShadow.frame = bounds
        sideShadowMask.frame = bounds
        topShadow.frame = bounds
        projectionGroup.frame = bounds
        validityMask.frame = bounds
        projectedContainer.frame = bounds
        verticalContainer.frame = bounds
        backdrop.layer.frame = bounds
        edgeBackdrop.layer.frame = bounds
        revealMask.frame = bounds
        sideFeather.frame = bounds
        CATransaction.commit()
    }

    func setRadius(_ radius: Double) {
        requestedRadius = radius
        applyRadii(progress: max(lastProgress, 0))
    }

    func showLayers(edge: Bool, projected: Bool, reveal: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let feathered = reveal || (edge && projected)
        sideShadow.isHidden = !feathered
        topShadow.isHidden = !feathered
        projectionGroup.isHidden = !edge && !projected
        projectionGroup.mask = feathered ? validityMask : nil
        edgeBackdrop.layer.isHidden = !edge
        projectedContainer.isHidden = !projected
        projectedContainer.mask = feathered ? sideFeather : nil
        verticalContainer.mask = feathered ? revealMask : nil
        CATransaction.commit()
        lastProgress = -1
    }

    func update(progress: Double, tuning: EffectTuning) {
        guard abs(progress - lastProgress) > 0.00001 || tuning.perspectiveDepth != lastDepth
                || tuning.edgeDissolve != lastEdgeDissolve else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mesh = progress < 0.0001 ? nil : FoldProjectionMesh.make(progress: progress, tuning: tuning)
        edgeBackdrop.layer.setValue(mesh, forKey: "meshTransform")
        backdrop.layer.setValue(mesh, forKey: "meshTransform")
        projectionGroup.frame = bounds
        projectedContainer.frame = bounds
        verticalContainer.frame = bounds
        backdrop.layer.frame = bounds
        edgeBackdrop.layer.frame = bounds
        if abs(progress - lastMaskProgress) > 0.001 || tuning.perspectiveDepth != lastMaskDepth {
            ProjectionValidityMask.update(validityMask, sideShadow: sideShadowMask,
                                          bounds: bounds, progress: progress, tuning: tuning)
            lastMaskProgress = progress
            lastMaskDepth = tuning.perspectiveDepth
        }
        BlurRevealMask.updateSideFeather(sideFeather, bounds: bounds, progress: progress)
        BlurRevealMask.update(revealMask, bounds: bounds, progress: progress, tuning: tuning)
        BlurRevealMask.updateTopShadow(topShadow, bounds: bounds, progress: progress, tuning: tuning)
        CATransaction.commit()
        applyRadii(progress: progress)
        lastProgress = progress
        lastDepth = tuning.perspectiveDepth
        lastEdgeDissolve = tuning.edgeDissolve
    }

    private func applyRadii(progress: Double) {
        let baseRadius = Int(max(1, (requestedRadius * FoldAppearance.backgroundBlurFactor(progress: progress)).rounded()))
        let projectedRadius = Int(max(1, requestedRadius.rounded()))
        if baseRadius != lastBaseRadius {
            edgeBackdrop.setRadius(Double(baseRadius))
            lastBaseRadius = baseRadius
        }
        if projectedRadius != lastProjectedRadius {
            backdrop.setRadius(Double(projectedRadius))
            lastProjectedRadius = projectedRadius
        }
    }
}
