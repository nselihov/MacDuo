import AppKit
import CoreImage
import MacDuoCore
import SwiftUI

/// A small in-window preview. Only image acquisition/blur differ from the
/// fullscreen WindowServer backend; optical values and the mask are shared.
struct FoldPreviewSurface: NSViewRepresentable {
    let frameStore: DesktopFrameStore
    let parameters: FoldParameters
    let tuning: EffectTuning
    let hasDesktopFrame: Bool

    func makeNSView(context: Context) -> FoldPreviewView {
        FoldPreviewView(frameStore: frameStore)
    }

    func updateNSView(_ view: FoldPreviewView, context: Context) {
        view.update(parameters: parameters, tuning: tuning, hasDesktopFrame: hasDesktopFrame)
    }
}

@MainActor
final class FoldPreviewView: NSView {
    private let frameStore: DesktopFrameStore
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let sharp = NSImageView()
    private let effect = NSView()
    private let projectionGroup = NSView()
    private let softBlurred = NSImageView()
    private let projected = NSView()
    private let verticalProjected = NSView()
    private let blurred = NSImageView()
    private let revealMask = BlurRevealMask.make()
    private let sideFeather = BlurRevealMask.makeSideFeather()
    private let validityMask = ProjectionValidityMask.makeLayer()
    private let sideShadow = NSView()
    private let sideShadowMask = ProjectionValidityMask.makeLayer()
    private let topShadow = NSView()
    private let topShadowGradient = BlurRevealMask.makeTopShadow()
    private let mask = FoldMaskView(frame: .zero)
    private var timer: Timer?
    private var targetProgress = 0.0
    private var targetRadius = 0.0
    private var progress = 0.0
    private var radius = 0.0
    private var tuning = EffectTuning.standard
    private var hasDesktopFrame = false
    private var lastTick = CACurrentMediaTime()
    private var lastGeneration: UInt64?
    private var lastBaseRadius = -1.0
    private var lastProjectedRadius = -1.0
    private var lastProjectionProgress = -1.0
    private var lastProjectionDepth = -1.0
    private var imageSize = CGSize.zero
    private var image: CIImage?
    private var referenceHeight: CGFloat = 900
    var hasRenderedFrame: Bool { sharp.image != nil && softBlurred.image != nil && blurred.image != nil }

    init(frameStore: DesktopFrameStore) {
        self.frameStore = frameStore
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        sharp.imageScaling = .scaleAxesIndependently
        projectionGroup.wantsLayer = true
        projectionGroup.layer?.mask = validityMask
        softBlurred.imageScaling = .scaleAxesIndependently
        softBlurred.wantsLayer = true
        blurred.imageScaling = .scaleAxesIndependently
        projected.wantsLayer = true
        projected.layer?.mask = sideFeather
        verticalProjected.wantsLayer = true
        verticalProjected.layer?.mask = revealMask
        blurred.wantsLayer = true
        effect.wantsLayer = true
        sideShadow.wantsLayer = true
        sideShadow.layer?.backgroundColor = NSColor.black.cgColor
        sideShadow.layer?.mask = sideShadowMask
        topShadow.wantsLayer = true
        topShadow.layer?.addSublayer(topShadowGradient)
        addSubview(sharp)
        addSubview(effect)
        effect.addSubview(projectionGroup)
        projectionGroup.addSubview(softBlurred)
        projectionGroup.addSubview(projected)
        projected.addSubview(verticalProjected)
        verticalProjected.addSubview(blurred)
        effect.addSubview(sideShadow)
        effect.addSubview(topShadow)
        effect.addSubview(mask)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(parameters: FoldParameters, tuning: EffectTuning, hasDesktopFrame: Bool) {
        self.tuning = tuning.clamped()
        targetProgress = parameters.progress
        targetRadius = FoldAppearance.blurRadius(parameters: parameters, tuning: tuning)
        if self.hasDesktopFrame != hasDesktopFrame {
            image = nil
            lastGeneration = nil
        }
        self.hasDesktopFrame = hasDesktopFrame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func layout() {
        super.layout()
        sharp.frame = bounds
        effect.frame = bounds
        sideShadow.frame = bounds
        sideShadowMask.frame = bounds
        topShadow.frame = bounds
        projectionGroup.frame = bounds
        validityMask.frame = bounds
        softBlurred.frame = bounds
        projected.frame = bounds
        verticalProjected.frame = bounds
        blurred.frame = bounds
        revealMask.frame = bounds
        sideFeather.frame = bounds
        mask.frame = bounds
        referenceHeight = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0
        })?.frame.height ?? 900
    }

    private func tick() {
        guard bounds.width > 0, bounds.height > 0,
              !isHiddenOrHasHiddenAncestor, window?.occlusionState.contains(.visible) == true else { return }
        let now = CACurrentMediaTime()
        let response = FoldAppearance.response(deltaTime: now - lastTick, responseSeconds: tuning.responseSeconds)
        lastTick = now
        progress += (targetProgress - progress) * response
        radius += (targetRadius - radius) * response
        if targetRadius == 0, radius < 0.03, progress < 0.0001 { progress = 0; radius = 0 }
        mask.update(progress: progress, tuning: tuning)
        BlurRevealMask.update(revealMask, bounds: bounds, progress: progress, tuning: tuning)
        BlurRevealMask.updateSideFeather(sideFeather, bounds: bounds, progress: progress)
        BlurRevealMask.updateTopShadow(topShadowGradient, bounds: bounds, progress: progress, tuning: tuning)
        if abs(progress - lastProjectionProgress) > 0.00001 || tuning.perspectiveDepth != lastProjectionDepth {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let mesh = progress < 0.0001 ? nil : FoldProjectionMesh.make(progress: progress, tuning: tuning)
            softBlurred.layer?.setValue(mesh, forKey: "meshTransform")
            blurred.layer?.setValue(mesh, forKey: "meshTransform")
            ProjectionValidityMask.update(validityMask, sideShadow: sideShadowMask,
                                          bounds: bounds, progress: progress, tuning: tuning)
            CATransaction.commit()
            lastProjectionProgress = progress
            lastProjectionDepth = tuning.perspectiveDepth
        }
        effect.alphaValue = FoldAppearance.opacity(radius: radius, progress: progress)

        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        let snapshot = hasDesktopFrame ? frameStore.snapshot() : nil
        let sourceChanged = image == nil || size != imageSize || snapshot?.generation != lastGeneration
        if sourceChanged {
            let source: CIImage
            if let snapshot {
                source = CIImage(cvPixelBuffer: snapshot.pixelBuffer)
            } else {
                let renderer = ImageRenderer(content: SpatialArtwork().frame(width: bounds.width, height: bounds.height))
                renderer.scale = scale
                guard let artwork = renderer.cgImage else { return }
                source = CIImage(cgImage: artwork)
            }
            let fit = max(size.width / source.extent.width, size.height / source.extent.height)
            let resized = source.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            image = resized.transformed(by: CGAffineTransform(
                translationX: (size.width - resized.extent.width) / 2 - resized.extent.minX,
                y: (size.height - resized.extent.height) / 2 - resized.extent.minY
            )).cropped(to: CGRect(origin: .zero, size: size))
            imageSize = size
            lastGeneration = snapshot?.generation
            if let image, let cg = context.createCGImage(image, from: image.extent) {
                sharp.image = NSImage(cgImage: cg, size: bounds.size)
            }
        }
        let previewScale = Double(bounds.height / referenceHeight * scale)
        let projectedRadius = max(radius.rounded(), 1) * previewScale
        let baseRadius = max((radius * FoldAppearance.backgroundBlurFactor(progress: progress)).rounded(), 1) * previewScale
        if sourceChanged || abs(baseRadius - lastBaseRadius) > 0.01 {
            guard let image else { return }
            let result = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: baseRadius])
                .cropped(to: image.extent)
            if let cg = context.createCGImage(result, from: image.extent) {
                softBlurred.image = NSImage(cgImage: cg, size: bounds.size)
                lastBaseRadius = baseRadius
            }
        }
        if sourceChanged || abs(projectedRadius - lastProjectedRadius) > 0.01 {
            guard let image else { return }
            let result = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: projectedRadius])
                .cropped(to: image.extent)
            if let cg = context.createCGImage(result, from: image.extent) {
                blurred.image = NSImage(cgImage: cg, size: bounds.size)
                lastProjectedRadius = projectedRadius
            }
        }
    }

    deinit { timer?.invalidate() }
}
