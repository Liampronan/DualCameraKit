import UIKit

/// Central camera controller
public final class DualCameraController {
    
    private let streamSource = CameraStreamSource()
    
    // Main renderer reference for capture
    private(set) weak var primaryRenderer: CameraRenderer?
    
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
    @MainActor
    public func createRenderer() -> CameraRenderer {
        let renderer = MetalCameraRenderer()
        return renderer
    }
    
    /// Register renderer as primary for capture
    public func setPrimaryRenderer(_ renderer: CameraRenderer) {
        primaryRenderer = renderer
    }
    
//    @MainActor
    /// Capture photo from primary renderer
    public func capturePhoto() async throws -> UIImage {
        guard let renderer = primaryRenderer else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        return try await renderer.captureFrame()
    }
}

