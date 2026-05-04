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

/// Metal-accelerated camera renderer.
public final class MetalCameraRenderer: MTKView, CameraRenderer, MTKViewDelegate {

    // MARK: - Metal State
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private let latestFrameStore = LatestPixelBufferStore()
    public var cameraContentMode: DualCameraContentMode = .aspectFill

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

        framebufferOnly = false
        preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        isPaused = false
        enableSetNeedsDisplay = false
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
    public var view: UIView { self }

    public nonisolated func update(with frame: PixelBufferWrapper) {
        latestFrameStore.store(frame)
    }
}

// MARK: - MTKViewDelegate

extension MetalCameraRenderer {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle view size changes if needed.
    }

    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let pipelineState = renderPipelineState,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        commandEncoder.setRenderPipelineState(pipelineState)

        if let texture = makeTexture(fromLatestFrame: latestFrameStore.latestValue) {
            let scale = calculateScale(for: texture, in: view.drawableSize, contentMode: cameraContentMode)
            var uniforms = Uniforms(scale: scale)
            commandEncoder.setVertexBytes(&uniforms,
                                          length: MemoryLayout<Uniforms>.size,
                                          index: 0)
            commandEncoder.setFragmentTexture(texture, index: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip,
                                          vertexStart: 0,
                                          vertexCount: 4)
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeTexture(fromLatestFrame frame: PixelBufferWrapper?) -> MTLTexture? {
        guard let textureCache = self.textureCache else {
            DualCameraLogger.errors.error("No texture cache available")
            return nil
        }

        guard let frame else { return nil }

        let buffer = frame.buffer
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

        return metalTexture
    }

    private func calculateScale(
        for texture: MTLTexture,
        in drawableSize: CGSize,
        contentMode: DualCameraContentMode
    ) -> SIMD2<Float> {
        let textureAspect = Float(texture.width) / Float(texture.height)
        let viewAspect = Float(drawableSize.width) / Float(drawableSize.height)

        switch contentMode {
        case .aspectFill:
            return textureAspect > viewAspect
            ? SIMD2<Float>(textureAspect / viewAspect, 1)
            : SIMD2<Float>(1, viewAspect / textureAspect)
        case .aspectFit:
            return textureAspect > viewAspect
            ? SIMD2<Float>(1, viewAspect / textureAspect)
            : SIMD2<Float>(textureAspect / viewAspect, 1)
        }
    }
}

private final class LatestPixelBufferStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PixelBufferWrapper?

    func store(_ newValue: PixelBufferWrapper) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var latestValue: PixelBufferWrapper? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
