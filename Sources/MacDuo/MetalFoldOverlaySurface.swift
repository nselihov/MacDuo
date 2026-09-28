import AppKit
import CoreVideo
import MacDuoCore
import MacDuoSkyLight
import Metal
import MetalKit
import SwiftUI

/// Experimental desktop-only path. The reference shader receives the same
/// ScreenCaptureKit frames as the existing mini preview. Lock-screen capture
/// is intentionally outside this experiment.
@MainActor
final class MetalFoldOverlaySurface {
    private let bridge: SkyLightBridge
    private let view: MetalFoldView
    let window: NSWindow
    private var lease: SkyLightWindowLease?
    private var lastTick = CACurrentMediaTime()
    private var tuning = EffectTuning.standard
    private var parameters = FoldMotionModel.parameters(angle: 115, velocity: 0)
    private var progress = 0.0
    private var radius = 0.0
    private var targetProgress = 0.0
    private var targetRadius = 0.0
    private var isPresented = false
    private var lastInputProgress: Double?
    private var lastInputMotionTime = CACurrentMediaTime()

    init(screen: NSScreen, bridge: SkyLightBridge, frameStore: DesktopFrameStore) throws {
        self.bridge = bridge
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SkyLightBridge.Failure.unavailable("Metal device")
        }
        let shaderURL = Bundle.main.resourceURL!.appendingPathComponent("DuoFold.metal")
        view = try MetalFoldView(frame: bounds, device: device,
                                 frameStore: frameStore, shaderURL: shaderURL)
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.canHide = false
        window.level = .init(rawValue: Int(Int32.max - 2))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
        window.animationBehavior = .none
        window.contentView = view
        view.autoresizingMask = [.width, .height]
        // Drive the optical state from the same display callback that draws
        // it. A separate 60 Hz timer can land just after a Metal frame and
        // show the previous angle for another refresh interval.
        view.beforeDraw = { [weak self] in self?.tick() }
    }

    func show(on screen: NSScreen, parameters: FoldParameters,
              tuning: EffectTuning) throws {
        self.parameters = parameters
        self.tuning = tuning.clamped()
        targetProgress = parameters.progress
        targetRadius = FoldAppearance.angleBlurRadius(progress: parameters.progress, tuning: tuning)
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        if !isPresented {
            view.beginPresentation()
            lastInputProgress = parameters.progress
            lastInputMotionTime = CACurrentMediaTime()
            window.alphaValue = 0.001
            lease = try bridge.makeWindowLease(for: window)
            try bridge.present(window)
            isPresented = true
            view.isPaused = false
            lastTick = CACurrentMediaTime()
        } else {
            if let lastInputProgress,
               abs(parameters.progress - lastInputProgress) > 0.0005 {
                lastInputMotionTime = CACurrentMediaTime()
                view.setInputFrozen(true)
                self.lastInputProgress = parameters.progress
            }
        }
    }

    func retire(tuning: EffectTuning) {
        guard isPresented else { return }
        self.tuning = tuning.clamped()
        targetProgress = 0
        targetRadius = 0
    }

    func hideImmediately() {
        guard isPresented || lease != nil else { return }
        view.isPaused = true
        view.endPresentation()
        lastInputProgress = nil
        lease?.cancel()
        lease = nil
        window.alphaValue = 0
        window.orderOut(nil)
        bridge.conceal()
        isPresented = false
        progress = 0
        radius = 0
    }

    func close() { hideImmediately(); window.close() }

    private func tick() {
        guard isPresented else { return }
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now
        let response = FoldAppearance.response(deltaTime: dt,
                                               responseSeconds: tuning.responseSeconds)
        progress += (targetProgress - progress) * response
        radius += (targetRadius - radius) * response
        if now - lastInputMotionTime > 0.7 {
            view.setInputFrozen(false)
        }
        let lod = min(max(radius / 80 * 8, 0), 8)
        view.setOptics(progress: progress,
                       eyeDistance: 3.1 / tuning.perspectiveDepth,
                       maxBlurLOD: lod,
                       transitionWidth: tuning.edgeDissolve)
        window.alphaValue = FoldAppearance.opacity(radius: radius, progress: progress)
        lease?.renew(alpha: window.alphaValue)
        if targetRadius == 0, radius < 0.03, progress < 0.0001 { hideImmediately() }
    }
}

@MainActor
private final class MetalFoldView: MTKView, MTKViewDelegate {
    private struct TextureLifetime: @unchecked Sendable {
        // Core Video owns the immutable capture texture until this command
        // finishes; the wrapper only transfers that lifetime across queues.
        let texture: CVMetalTexture
    }

    private struct Uniforms {
        var progress: Float = 0
        var eyeDistance: Float = 3.1
        var maxBlurLOD: Float = 8
        var transitionWidth: Float = 1
    }

    private let frameStore: DesktopFrameStore
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?
    private var cachedGeneration: UInt64?
    private var mipTexture: MTLTexture?
    private var inputFrozen = false
    private var freezeAfterNextFrame = false
    private var uniforms = Uniforms()
    var beforeDraw: (() -> Void)?

    init(frame: CGRect, device: MTLDevice, frameStore: DesktopFrameStore,
         shaderURL: URL) throws {
        self.frameStore = frameStore
        guard let queue = device.makeCommandQueue() else {
            throw SkyLightBridge.Failure.unavailable("Metal command queue")
        }
        self.queue = queue
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "renderDuoFold") else {
            throw SkyLightBridge.Failure.unavailable("Duo fold shader")
        }
        pipeline = try device.makeComputePipelineState(function: function)
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = true
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        delegate = self
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func setOptics(progress: Double, eyeDistance: Double,
                   maxBlurLOD: Double, transitionWidth: Double) {
        uniforms.progress = Float(progress)
        uniforms.eyeDistance = Float(eyeDistance)
        uniforms.maxBlurLOD = Float(maxBlurLOD)
        uniforms.transitionWidth = Float(transitionWidth)
    }

    func beginPresentation() {
        // The first frame belongs to the current display session. Hold it
        // while the lid moves so macOS window rearrangement is not projected
        // as motion across the folding glass.
        cachedGeneration = nil
        mipTexture = nil
        inputFrozen = false
        freezeAfterNextFrame = true
    }

    func setInputFrozen(_ frozen: Bool) {
        if frozen {
            if mipTexture != nil { inputFrozen = true }
            else { freezeAfterNextFrame = true }
        } else {
            inputFrozen = false
            freezeAfterNextFrame = false
        }
    }

    func endPresentation() {
        inputFrozen = false
        freezeAfterNextFrame = false
        cachedGeneration = nil
        mipTexture = nil
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { drawFrame() }
    }

    private func drawFrame() {
        beforeDraw?()
        guard !isPaused else { return }
        guard let drawable = currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        var retainedTexture: CVMetalTexture?
        if !inputFrozen,
           let snapshot = frameStore.snapshot(), snapshot.generation != cachedGeneration,
           let textureCache {
            let buffer = snapshot.pixelBuffer
            var wrapped: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &wrapped)
            if result == kCVReturnSuccess, let wrapped,
               let captureTexture = CVMetalTextureGetTexture(wrapped) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: captureTexture.width,
                    height: captureTexture.height, mipmapped: true)
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .private
                if let next = device?.makeTexture(descriptor: descriptor),
                   let blit = command.makeBlitCommandEncoder() {
                    blit.copy(from: captureTexture, sourceSlice: 0, sourceLevel: 0,
                              sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                              sourceSize: MTLSize(width: captureTexture.width,
                                                  height: captureTexture.height, depth: 1),
                              to: next, destinationSlice: 0, destinationLevel: 0,
                              destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                    blit.generateMipmaps(for: next)
                    blit.endEncoding()
                    mipTexture = next
                    cachedGeneration = snapshot.generation
                    retainedTexture = wrapped
                    if freezeAfterNextFrame {
                        inputFrozen = true
                        freezeAfterNextFrame = false
                    }
                }
            }
        }
        guard let mipTexture,
              let encoder = command.makeComputeCommandEncoder() else { return }
        var values = uniforms
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(mipTexture, index: 0)
        encoder.setTexture(drawable.texture, index: 1)
        encoder.setBytes(&values, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: drawable.texture.width,
                                        height: drawable.texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        command.present(drawable)
        if let retainedTexture {
            let lifetime = TextureLifetime(texture: retainedTexture)
            command.addCompletedHandler { _ in _ = lifetime }
        }
        command.commit()
    }
}

/// The live in-app preview uses the same pixel projection as the desktop
/// overlay. The old Core Animation preview remains for placeholder artwork.
struct MetalFoldPreviewSurface: NSViewRepresentable {
    let frameStore: DesktopFrameStore
    let parameters: FoldParameters
    let tuning: EffectTuning

    func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let shaderURL = Bundle.main.resourceURL?.appendingPathComponent("DuoFold.metal"),
              let view = try? MetalFoldView(frame: .zero, device: device,
                                            frameStore: frameStore, shaderURL: shaderURL) else {
            return FoldPreviewView(frameStore: frameStore)
        }
        view.isPaused = false
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let metal = view as? MetalFoldView {
            let normalized = tuning.clamped()
            let radius = FoldAppearance.angleBlurRadius(progress: parameters.progress, tuning: normalized)
            metal.setOptics(progress: parameters.progress,
                            eyeDistance: 3.1 / normalized.perspectiveDepth,
                            maxBlurLOD: min(max(radius / 80 * 8, 0), 8),
                            transitionWidth: normalized.edgeDissolve)
        } else if let fallback = view as? FoldPreviewView {
            fallback.update(parameters: parameters, tuning: tuning, hasDesktopFrame: true)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? MetalFoldView)?.isPaused = true
    }
}
