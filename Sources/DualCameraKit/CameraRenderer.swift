import AVFoundation
import MetalKit
import UIKit

/// Protocol defining camera rendering capabilities
public protocol CameraRenderer: AnyObject {
    /// Update renderer with new camera frame
    func update(with buffer: CVPixelBuffer)
    
    /// Capture current frame as UIImage
    func captureCurrentFrame() async throws -> UIImage
}

private class FrameStore {
    nonisolated(unsafe) static let shared = FrameStore()
    private let queue = DispatchQueue(label: "com.app.framestore")
    private var buffers: [Int: CVPixelBuffer] = [:]
    
    func store(_ buffer: CVPixelBuffer) -> Int {
        let ptr = unsafeBitCast(buffer, to: Int.self)
        queue.sync { buffers[ptr] = buffer }
        return ptr
    }
    
    func retrieve(_ ptr: Int) -> CVPixelBuffer? {
        queue.sync { buffers[ptr] }
    }
    
    func release(_ ptr: Int) {
        queue.sync { buffers.removeValue(forKey: ptr) }
    }
}


/// Metal-accelerated camera renderer
public final class MetalCameraRenderer: MTKView, MTKViewDelegate, CameraRenderer {
    // Metal state
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private var currentTexture: MTLTexture?
    private let renderActor = RenderActor()

    
    public required init(coder: NSCoder) {
        super.init(coder: coder)
        try? initializeMetal()
        self.delegate = self
    }
    
    public override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        try? initializeMetal()
        self.delegate = self
    }
    
    /// Update with new camera frame
    // PATTERN: Direct-to-Main with atomic state transfer
    // Remove all protocol complexity - simplify to basics
    public nonisolated func update(with buffer: CVPixelBuffer) {
        let ptr = FrameStore.shared.store(buffer)
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let buffer = FrameStore.shared.retrieve(ptr) else { return }
            
            // Create texture on main thread using retrieved buffer
            self.createAndUpdateTexture(from: buffer)
            FrameStore.shared.release(ptr)
        }
    }
    
    @MainActor
    private func createAndUpdateTexture(from buffer: CVPixelBuffer) {
        guard let textureCache = self.textureCache else {
            print("⚠️ No texture cache available")
            return
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        // Create CVMetalTexture
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
        
        // Extract MTLTexture
        guard status == kCVReturnSuccess,
              let textureRef = textureRef,
              let metalTexture = CVMetalTextureGetTexture(textureRef) else {
            print("❌ Failed to create texture: \(status)")
            return
        }
        
        // Update renderer state
        self.currentTexture = metalTexture
        self.setNeedsDisplay()
    }

    // Keep all texture work on main thread
    @MainActor private func processFrameOnMainThread(
        _ buffer: CVPixelBuffer,
        width: Int,
        height: Int,
        time: CFAbsoluteTime
    ) {
        // Create texture directly on MT - solves ALL data race issues
        guard let textureCache = self.textureCache else { return }
        
        var textureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm,
            width, height, 0, &textureRef
        )
        
        if let texture = textureRef.flatMap(CVMetalTextureGetTexture) {
            self.currentTexture = texture
            self.setNeedsDisplay()
        }
    }

    // Helper stays on main thread - no isolation issues
    private func createTextureFromBuffer(_ buffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        
        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
            0, &textureRef
        )
        
        return status == kCVReturnSuccess ? CVMetalTextureGetTexture(textureRef!) : nil
    }
        
        // Recreates texture from raw data
        @MainActor private func recreateTexture(from info: TextureInfo) {
            guard let device else { return }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: info.pixelFormat,
                width: info.width,
                height: info.height,
                mipmapped: false
            )
            
            guard let newTexture = device.makeTexture(descriptor: descriptor) else { return }
            
            let region = MTLRegionMake2D(0, 0, info.width, info.height)
            info.data.withUnsafeBytes { ptr in
                newTexture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: info.bytesPerRow
                )
            }
            
            currentTexture = newTexture
            setNeedsDisplay()
        }
    
    @MainActor
    public func captureCurrentFrame() async throws -> UIImage {
        // Ensure we have a current drawable to capture from
        guard let drawable = currentDrawable else {
            throw DualCameraError.captureFailure(.noTextureAvailable)
        }
        
        let texture = drawable.texture
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let bytesPerImage = bytesPerRow * height

        // Allocate buffer for the texture data
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytesPerImage, alignment: 8)
        defer { buffer.deallocate() }
        
        // Copy texture data into the buffer
        texture.getBytes(buffer,
                         bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height),
                         mipmapLevel: 0)
        
        // Create a CGContext using sRGB color space to prevent color shifts
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let cgImage = context.makeImage() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Required MTKViewDelegate implementation
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes
    }
    
    /// Render frame to Metal view
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
    
    private func calculateAspectFitScale(for texture: MTLTexture, in drawableSize: CGSize) -> SIMD2<Float> {
        let textureAspect = Float(texture.width) / Float(texture.height)
        let viewAspect = Float(drawableSize.width) / Float(drawableSize.height)
        return textureAspect > viewAspect
            ? SIMD2<Float>(textureAspect / viewAspect, 1)
            : SIMD2<Float>(1, viewAspect / textureAspect)
    }
    
    /// Initialize Metal rendering pipeline
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
}

struct TextureInfo: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelFormat: MTLPixelFormat
    let data: Data // Copy of pixel data (sendable)
}

// Processing actor
private actor RenderActor {
    func extractTextureInfo(_ wrapper: PixelBufferWrapper) -> TextureInfo? {
        let buffer = wrapper.buffer
        
        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        // Extract parameters
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        // Copy pixel data to Data (sendable)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let dataSize = bytesPerRow * height
        let data = Data(bytes: baseAddress, count: dataSize)
        
        return TextureInfo(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            pixelFormat: .bgra8Unorm,
            data: data
        )
    }
}
