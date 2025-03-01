import AVFoundation
import MetalKit
import UIKit

/// Camera rendering capabilities.
public protocol CameraRenderer: AnyObject {
    /// Update renderer with new camera frame.
    func update(with buffer: CVPixelBuffer)
    
    /// Capture current frame as UIImage.
    func captureCurrentFrame() async throws -> UIImage
}

/// Metal-accelerated camera renderer.
public final class MetalCameraRenderer: MTKView, CameraRenderer, MTKViewDelegate {
    
    // MARK: - Metal State
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private var currentTexture: MTLTexture?
    
    // MARK: - Initialization
    public required init(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
        
        do {
            try initializeMetal()
        } catch {
            #if DEBUG
            fatalError("❌ Could not initialize Metal: \(error.localizedDescription)")
            #else
            DualCameraLogger.errors.error("❌ Could not initialize Metal (release mode)")
            setupFallbackView()
            #endif
        }
    }

    public override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        self.delegate = self
        
        do {
            try initializeMetal()
        } catch {
            #if DEBUG
            fatalError("❌ Could not initialize Metal: \(error.localizedDescription)")
            #else
            DualCameraLogger.errors.error("❌ Could not initialize Metal (release mode)")
            setupFallbackView()
            #endif
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
    
    nonisolated public func update(with buffer: CVPixelBuffer) {
        let bufferWrapper = PixelBufferWrapper(buffer: buffer)
        Task { @MainActor [weak self] in
            self?.createAndUpdateTexture(from: bufferWrapper)
        }
    }
    
    /// Captures the current frame by reading the drawable’s texture.
    public func captureCurrentFrame() async throws -> UIImage {
        // Ensure we have a valid texture to capture from
        guard let currentTexture = self.currentTexture else {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        
        // Create a texture descriptor for the destination texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: currentTexture.pixelFormat,
            width: currentTexture.width,
            height: currentTexture.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        
        guard let device = self.device,
              let destinationTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw DualCameraError.captureFailure(.textureCreationFailed)
        }
        
        // Create a command buffer and encoder to copy the texture
        guard let commandBuffer = self.commandQueue?.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw DualCameraError.captureFailure(.commandBufferCreationFailed)
        }
        
        // Copy the texture
        blitEncoder.copy(from: currentTexture,
                        sourceSlice: 0,
                        sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: currentTexture.width,
                                            height: currentTexture.height,
                                            depth: 1),
                        to: destinationTexture,
                        destinationSlice: 0,
                        destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert the Metal texture to a CGImage
        let bytesPerRow = 4 * currentTexture.width
        let totalBytes = bytesPerRow * currentTexture.height
        
        let regionSize = MTLSizeMake(currentTexture.width, currentTexture.height, 1)
        let region = MTLRegionMake2D(0, 0, currentTexture.width, currentTexture.height)
        
        // Create a bitmap context
        guard let rawData = malloc(totalBytes) else {
            throw DualCameraError.captureFailure(.memoryAllocationFailed)
        }
        
        destinationTexture.getBytes(rawData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // IMPORTANT: For BGRA texture format, we need to specify the correct bitmap info
        // Metal uses BGRA format, so we need to tell CGContext that
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let context = CGContext(data: rawData,
                                     width: currentTexture.width,
                                     height: currentTexture.height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: bytesPerRow,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: bitmapInfo.rawValue) else {
            free(rawData)
            throw DualCameraError.captureFailure(.contextCreationFailed)
        }
        
        // Create the CGImage
        guard let cgImage = context.makeImage() else {
            free(rawData)
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        
        // Clean up
        free(rawData)
        
        // Create and return the UIImage
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
    
    
    // MARK: - Private Helpers
    
    /// Creates a texture from the given buffer and updates the view.
    @MainActor
    private func createAndUpdateTexture(from bufferWrapper: PixelBufferWrapper) {
        guard let textureCache = self.textureCache else {
            print("⚠️ No texture cache available")
            return
        }
        let buffer = bufferWrapper.buffer
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
              let textureRef = textureRef,
              let metalTexture = CVMetalTextureGetTexture(textureRef) else {
            print("❌ Failed to create texture: \(status)")
            return
        }
        
        self.currentTexture = metalTexture
        self.setNeedsDisplay()
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
    
    /// Calculates a scale to aspect-fit the texture within the drawable size.
    private func calculateAspectFitScale(for texture: MTLTexture, in drawableSize: CGSize) -> SIMD2<Float> {
        let textureAspect = Float(texture.width) / Float(texture.height)
        let viewAspect = Float(drawableSize.width) / Float(drawableSize.height)
        return textureAspect > viewAspect
            ? SIMD2<Float>(textureAspect / viewAspect, 1)
            : SIMD2<Float>(1, viewAspect / textureAspect)
    }
}

