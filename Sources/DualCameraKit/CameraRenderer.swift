import AVFoundation
import MetalKit
import UIKit

/// Protocol defining camera rendering capabilities
public protocol CameraRenderer: AnyObject {
    /// Update renderer with new camera frame
    func update(with buffer: CVPixelBuffer)
    
    /// Capture current frame as UIImage
    func captureFrame() async throws -> UIImage
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
    public nonisolated func update(with buffer: CVPixelBuffer) {
        // Wrap non-sendable buffer
        let wrapper = PixelBufferWrapper(buffer: buffer)
        Task {
            // Extract texture info on background actor
            if let textureInfo = await renderActor.extractTextureInfo(wrapper) {
                await MainActor.run { [weak self] in
                    self?.recreateTexture(from: textureInfo)
                }
            }
        }
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
    
    /// Capture current frame
    public func captureFrame() async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let drawable = self.currentDrawable else {
                    continuation.resume(throwing: DualCameraError.captureFailure(.noTextureAvailable))
                    return
                }
                let texture = drawable.texture
                // Create texture capture
                let width = texture.width
                let height = texture.height
                let bytesPerRow = width * 4
                let bytesPerImage = bytesPerRow * height
                let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytesPerImage, alignment: 8)
                defer { buffer.deallocate() }
                
                // Copy texture data
                texture.getBytes(buffer,
                               bytesPerRow: bytesPerRow,
                               from: MTLRegionMake2D(0, 0, width, height),
                               mipmapLevel: 0)
                
                // Create CGImage
                let context = CGContext(
                    data: buffer,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                
                if let cgImage = context?.makeImage() {
                    let image = UIImage(cgImage: cgImage)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: DualCameraError.captureFailure(.imageCreationFailed))
                }
            }
        }
    }
    
    /// Required MTKViewDelegate implementation
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes
    }
    
    /// Render frame to Metal view
    public func draw(in view: MTKView) {
        // Existing Metal drawing implementation
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
