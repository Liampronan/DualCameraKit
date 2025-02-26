import UIKit

/// Central camera controller
public final class DualCameraController {
    // Camera hardware
    private let streamSource = CameraStreamSource()
    
    // Main renderer reference for capture
    private(set) weak var primaryRenderer: CameraRenderer?
    
    /// Initialize controller
    public init() {}
    
    public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.frontCameraStream
    }
    
    public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.backCameraStream
    }
    
    /// Start camera session
    @MainActor
    public func startSession() async throws {
        try await streamSource.startSession()
    }
    
    /// Stop camera session
    public func stopSession() {
        streamSource.stopSession()
    }
    
    /// Create renderer for camera display
    /// - Returns: Metal-based camera renderer
    @MainActor
    public func createRenderer() -> CameraRenderer {
        let renderer = MetalCameraRenderer()
        return renderer
    }
    
    /// Register renderer as primary for capture
    /// - Parameter renderer: Renderer to use for capture
    public func setPrimaryRenderer(_ renderer: CameraRenderer) {
        primaryRenderer = renderer
    }
    
    /// Capture photo from primary renderer
    /// - Returns: Photo as UIImage
    public func capturePhoto() async throws -> UIImage {
        guard let renderer = primaryRenderer else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        return try await renderer.captureFrame()
    }
}

