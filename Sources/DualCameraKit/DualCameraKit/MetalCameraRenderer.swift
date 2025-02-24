import AVFoundation
import MetalKit
import os

/// Possible errors in MetalCameraRenderer
enum MetalRendererError: Error {
    case metalNotSupported
    case metalLibraryLoadFailed
    case metalFunctionNotFound
    case renderPipelineCreationFailed(Error)
    case textureCreationFailed
}

struct Uniforms {
    var scale: SIMD2<Float>
}

/// GPU-accelerated MetalKit view for rendering camera frames using Metal shaders.
/// This view should be used when rendering camera feeds with `DualCameraKit`.
public class MetalCameraRenderer: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private var currentTexture: MTLTexture?

    required init(coder: NSCoder) {
        super.init(coder: coder)
        do {
            try initializeMetal()
        } catch {
            DualCameraLogger.errors.error("❌ Metal initialization failed: \(error.localizedDescription)")
        }
    }
    // TODO: customize parameters, including framerate
    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        do {
            try initializeMetal()
        } catch {
            DualCameraLogger.errors.error("❌ Metal initialization failed: \(error.localizedDescription)")
        }
        self.delegate = self
    }

    /// Initializes Metal and sets up the rendering pipeline
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
        enableSetNeedsDisplay = true
        self.colorPixelFormat = .bgra8Unorm

        try setupRenderPipeline()
    }
    
    private struct MetalLibFunctionName {
        static let vertexShader = "vertexShader"
        static let fragmentShader = "fragmentShader"
    }
    
    /// Configures the Metal render pipeline
    private func setupRenderPipeline() throws {
        guard let device = device else {
            DualCameraLogger.errors.error("❌ No metal device found")
            throw MetalRendererError.metalLibraryLoadFailed
        }
        
        let frameworkBundle = Bundle(for: MetalCameraRenderer.self)
        
        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: frameworkBundle)
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

    /// Handles resizing of Metal view
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        DualCameraLogger.session.debug("🔄 Drawable size changed: \(size.debugDescription)")
    }

    /// Updates the Metal texture from a CVPixelBuffer
    public func update(with pixelBuffer: CVPixelBuffer) {
        guard let textureCache = textureCache else {
            DualCameraLogger.errors.error("❌ No Metal texture cache available")
            return
        }

        var textureRef: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &textureRef
        )

        guard status == kCVReturnSuccess, let texture = CVMetalTextureGetTexture(textureRef!) else {
            DualCameraLogger.errors.error("❌ Failed to create Metal texture from CVPixelBuffer")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentTexture = texture
            self?.setNeedsDisplay()
        }
    }

    /// Renders the Metal texture
    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let pipelineState = renderPipelineState,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        commandEncoder.setRenderPipelineState(pipelineState)

        if let texture = currentTexture {
            let scale = calculateAspectFitScale(for: texture, in: view.drawableSize)
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

    /// Computes the correct scaling to maintain aspect ratio
    private func calculateAspectFitScale(for texture: MTLTexture, in drawableSize: CGSize) -> SIMD2<Float> {
        let textureAspect = Float(texture.width) / Float(texture.height)
        let viewAspect = Float(drawableSize.width) / Float(drawableSize.height)
        return textureAspect > viewAspect
            ? SIMD2<Float>(textureAspect / viewAspect, 1)
            : SIMD2<Float>(1, viewAspect / textureAspect)
    }
}
