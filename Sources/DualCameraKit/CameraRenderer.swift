import AVFoundation
import MetalKit
import UIKit

/// Camera rendering capabilities.
@MainActor
public protocol CameraRenderer: AnyObject {
    /// Backing UIKit view used by SwiftUI adapters.
    var view: UIView { get }

    /// Controls how frames are scaled inside the renderer bounds.
    var cameraContentMode: DualCameraContentMode { get set }

    /// Update renderer with new camera frame.
    nonisolated func update(with frame: PixelBufferWrapper)
}

public extension CameraRenderer {
    /// Update renderer with a bare pixel buffer.
    nonisolated func update(with buffer: CVPixelBuffer) {
        update(with: PixelBufferWrapper(buffer: buffer))
    }
}

enum MetalRendererError: Error {
    case metalNotSupported
    case metalLibraryLoadFailed
    case metalFunctionNotFound
    case renderPipelineCreationFailed(Error)
    case textureCreationFailed
}

struct Uniforms {
    let scale: SIMD2<Float>
}

/// Retains a Core Video Metal texture wrapper alongside its `MTLTexture` across caching and GPU execution.
private struct CachedMetalTexture: @unchecked Sendable {
    let bufferID: ObjectIdentifier
    let cvTexture: CVMetalTexture
    let metalTexture: MTLTexture
}

/// Metal-accelerated camera renderer.
public final class MetalCameraRenderer: MTKView, CameraRenderer, MTKViewDelegate {

    // MARK: - Metal State
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private var cachedTexture: CachedMetalTexture?
    private let latestFrameStore = LatestPixelBufferStore()
    /// Controls how camera frames are scaled within the renderer view bounds.
    public var cameraContentMode: DualCameraContentMode = .aspectFill {
        didSet {
            guard cameraContentMode != oldValue else { return }
            setNeedsDisplay()
        }
    }

    // MARK: - Initialization
    public required init(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self

        do {
            try initializeMetal()
        } catch {
            DualCameraLogger.errors.error("❌ Could not initialize Metal: \(error.localizedDescription)")
            setupFallbackView()
        }
    }

    public override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        self.delegate = self

        do {
            try initializeMetal()
        } catch {
            DualCameraLogger.errors.error("❌ Could not initialize Metal: \(error.localizedDescription)")
            setupFallbackView()
        }
    }

    /// Initializes Metal components and sets up the render pipeline.
    private func initializeMetal() throws {
        guard let device = self.device else {
            DualCameraLogger.errors.error("❌ Metal not supported on this device")
            throw MetalRendererError.metalNotSupported
        }

        commandQueue = device.makeCommandQueue()

        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            DualCameraLogger.errors.error("❌ Failed to create Metal texture cache")
            throw MetalRendererError.textureCreationFailed
        }

        framebufferOnly = true
        preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        isPaused = true
        enableSetNeedsDisplay = true
        self.colorPixelFormat = .bgra8Unorm

        try setupRenderPipeline()
    }

    /// Helper constants for shader uniforms.
    private struct MetalLibFunctionName {
        static let vertexShader = "vertexShader"
        static let fragmentShader = "fragmentShader"
    }

    /// Sets up the Metal render pipeline.
    private func setupRenderPipeline() throws {
        guard let device = device else {
            DualCameraLogger.errors.error("❌ No metal device found")
            throw MetalRendererError.metalLibraryLoadFailed
        }

        let spmBundle = Bundle.module

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: spmBundle)
        } catch {
            DualCameraLogger.errors.error("❌ Failed to load Metal library: \(error.localizedDescription)")
            throw MetalRendererError.metalLibraryLoadFailed
        }

        guard let vertexFunction = library.makeFunction(name: MetalLibFunctionName.vertexShader),
              let fragmentFunction = library.makeFunction(name: MetalLibFunctionName.fragmentShader) else {
            DualCameraLogger.errors.error("❌ Metal functions not found in library")
            throw MetalRendererError.metalFunctionNotFound
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            DualCameraLogger.session.info("✅ Metal render pipeline initialized successfully")
        } catch {
            DualCameraLogger.errors.error("❌ Failed to create render pipeline: \(error.localizedDescription)")
            throw MetalRendererError.renderPipelineCreationFailed(error)
        }
    }

    // MARK: - Fallback View

    private func setupFallbackView() {
        // Clear any existing subviews and disable Metal rendering
        subviews.forEach { $0.removeFromSuperview() }
        isPaused = true
        enableSetNeedsDisplay = false

        // Create and add fallback view
        let fallbackView = CameraRendererFallbackView(frame: bounds)
        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackView)

        // Pin to edges
        NSLayoutConstraint.activate([
            fallbackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackView.topAnchor.constraint(equalTo: topAnchor),
            fallbackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - CameraRenderer Protocol Methods
extension MetalCameraRenderer {
    /// Backing UIKit view for this renderer.
    public var view: UIView { self }

    /// Stores the newest camera frame and schedules an on-demand redraw on the main actor.
    public nonisolated func update(with frame: PixelBufferWrapper) {
        let shouldScheduleRedraw = latestFrameStore.store(frame)
        guard shouldScheduleRedraw else { return }

        Task { @MainActor [weak self] in
            self?.consumePendingRedraw()
        }
    }

    /// Marks the pending redraw request as consumed and marks the view dirty.
    private func consumePendingRedraw() {
        latestFrameStore.markRedrawConsumed()
        setNeedsDisplay()
    }
}

// MARK: - MTKViewDelegate

extension MetalCameraRenderer {

    /// Requests a redraw when the drawable size changes.
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setNeedsDisplay()
    }

    /// Encodes and commits a Metal render pass for the latest camera frame.
    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let pipelineState = renderPipelineState,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        commandEncoder.setRenderPipelineState(pipelineState)

        if let frameTexture = makeTexture(fromLatestFrame: latestFrameStore.latestValue) {
            let texture = frameTexture.metalTexture
            let scale = calculateScale(for: texture, in: view.drawableSize, contentMode: cameraContentMode)
            var uniforms = Uniforms(scale: scale)
            commandEncoder.setVertexBytes(&uniforms,
                                          length: MemoryLayout<Uniforms>.size,
                                          index: 0)
            commandEncoder.setFragmentTexture(texture, index: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip,
                                          vertexStart: 0,
                                          vertexCount: 4)
            commandBuffer.addCompletedHandler { _ in
                withExtendedLifetime(frameTexture.cvTexture) {}
            }
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Creates or returns a cached Metal texture and its backing `CVMetalTexture` wrapper for the given frame.
    private func makeTexture(fromLatestFrame frame: PixelBufferWrapper?) -> CachedMetalTexture? {
        guard let textureCache = self.textureCache else {
            DualCameraLogger.errors.error("No texture cache available")
            return nil
        }

        guard let frame else { return nil }

        let buffer = frame.buffer
        let bufferID = ObjectIdentifier(buffer)
        if let cachedTexture, cachedTexture.bufferID == bufferID {
            return cachedTexture
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &textureRef
        )

        guard status == kCVReturnSuccess,
              let textureRef,
              let metalTexture = CVMetalTextureGetTexture(textureRef) else {
            DualCameraLogger.errors.error("Failed to create texture: \(status)")
            return nil
        }

        let cachedTexture = CachedMetalTexture(
            bufferID: bufferID,
            cvTexture: textureRef,
            metalTexture: metalTexture
        )
        self.cachedTexture = cachedTexture
        return cachedTexture
    }

    /// Computes the vertex scale factors for rendering `texture` in `drawableSize`.
    private func calculateScale(
        for texture: MTLTexture,
        in drawableSize: CGSize,
        contentMode: DualCameraContentMode
    ) -> SIMD2<Float> {
        DualCameraContentGeometry.rendererScale(
            for: CGSize(width: texture.width, height: texture.height),
            in: drawableSize,
            contentMode: contentMode
        )
    }
}

private final class LatestPixelBufferStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PixelBufferWrapper?
    private var hasPendingRedraw = false

    /// Stores the newest frame and returns `true` when the caller should schedule a main-actor redraw.
    func store(_ newValue: PixelBufferWrapper) -> Bool {
        lock.lock()
        value = newValue
        let shouldSchedule = !hasPendingRedraw
        hasPendingRedraw = true
        lock.unlock()
        return shouldSchedule
    }

    /// Clears the pending redraw flag before a scheduled draw occurs.
    func markRedrawConsumed() {
        lock.lock()
        hasPendingRedraw = false
        lock.unlock()
    }

    /// Returns the most recently stored pixel buffer wrapper.
    var latestValue: PixelBufferWrapper? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
