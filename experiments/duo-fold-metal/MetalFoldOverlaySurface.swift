import AppKit
import CoreVideo
import MacDuoCore
import MacDuoSkyLight
import Metal
import MetalKit

/// Experimental desktop-only path. The reference shader receives the same
/// ScreenCaptureKit frames as the existing mini preview. Lock-screen capture
/// is intentionally outside this experiment.
@MainActor
final class MetalFoldOverlaySurface {
    private let bridge: SkyLightBridge
    private let view: MetalFoldView
    private let window: NSWindow
    private var lease: SkyLightWindowLease?
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var tuning = EffectTuning.standard
    private var parameters = FoldMotionModel.parameters(angle: 115, velocity: 0)
    private var progress = 0.0
    private var radius = 0.0
    private var targetProgress = 0.0
    private var targetRadius = 0.0
    private var isPresented = false

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
    }

    func show(on screen: NSScreen, parameters: FoldParameters,
              tuning: EffectTuning) throws {
        self.parameters = parameters
        self.tuning = tuning.clamped()
        targetProgress = parameters.progress
        targetRadius = FoldAppearance.blurRadius(parameters: parameters, tuning: tuning)
        if !isPresented {
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0.001
            lease = try bridge.makeWindowLease(for: window)
            try bridge.present(window)
            isPresented = true
            view.isPaused = false
            lastTick = CACurrentMediaTime()
        }
        startTimer()
    }

    func retire(tuning: EffectTuning) {
        guard isPresented else { return }
        self.tuning = tuning.clamped()
        targetProgress = 0
        targetRadius = 0
        startTimer()
    }

    func hideImmediately() {
        timer?.invalidate()
        timer = nil
        view.isPaused = true
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

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now
        let response = FoldAppearance.response(deltaTime: dt,
                                               responseSeconds: tuning.responseSeconds)
        progress += (targetProgress - progress) * response
        radius += (targetRadius - radius) * response
        let lod = min(max(radius / 80 * 8, 0), 8)
        view.setOptics(progress: progress, imageAnchor: 0.55,
                       eyeDistance: 3.1 / tuning.perspectiveDepth,
                       maxBlurLOD: lod)
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
        var imageAnchor: Float = 0.55
        var eyeDistance: Float = 3.1
        var maxBlurLOD: Float = 8
    }

    private let frameStore: DesktopFrameStore
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?
    private var cachedGeneration: UInt64?
    private var mipTexture: MTLTexture?
    private var uniforms = Uniforms()

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

    func setOptics(progress: Double, imageAnchor: Double, eyeDistance: Double,
                   maxBlurLOD: Double) {
        uniforms.progress = Float(progress)
        uniforms.imageAnchor = Float(imageAnchor)
        uniforms.eyeDistance = Float(eyeDistance)
        uniforms.maxBlurLOD = Float(maxBlurLOD)
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { drawFrame() }
    }

    private func drawFrame() {
        guard let drawable = currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        var retainedTexture: CVMetalTexture?
        if let snapshot = frameStore.snapshot(), snapshot.generation != cachedGeneration,
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
