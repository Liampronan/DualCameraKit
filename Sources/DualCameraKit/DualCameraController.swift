import UIKit

/// Central camera controller
public final class DualCameraController { // TODO: remove this quick hack
    
    private let streamSource = CameraStreamSource()
    
    // Main renderer reference for capture
    private(set) weak var primaryRenderer: CameraRenderer? // TODO: remove me?
    private(set) weak var frontRenderer: CameraRenderer?
    private(set) weak var backRenderer: CameraRenderer?
    
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
    
    public func setRenderers(_ back: CameraRenderer, _ front: CameraRenderer) {
        backRenderer = back
        frontRenderer = front
    }
    
//    @MainActor
    /// Capture photo from primary renderer
    public func capturePhoto() async throws -> UIImage {
        guard let renderer = primaryRenderer else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        return try await renderer.captureCurrentFrame()
    }
    
    // TODO: customize this rendering - this is not necessarily matching layout
    // .... potentially there is a better way to align that
    public func captureCombinedPhoto() async throws -> UIImage {
        // Ensure both renderers are available
        guard let frontRenderer = frontRenderer, let backRenderer = backRenderer else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        // Capture frames from both cameras
        let backImage = try await backRenderer.captureCurrentFrame()
        let frontImage = try await frontRenderer.captureCurrentFrame()
        
        // Combine the images: Use backImage as background and overlay frontImage as PiP
        let size = backImage.size
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let combinedImage = renderer.image { ctx in
            // Draw the full-screen back image
            backImage.draw(in: CGRect(origin: .zero, size: size))
            
            // Define the PiP size (e.g., one-third of the full size) and position (e.g., top-right corner)
            let pipWidth = size.width / 3
            let pipHeight = size.height / 3
            let pipRect = CGRect(x: size.width - pipWidth - 10, y: 10, width: pipWidth, height: pipHeight)
            frontImage.draw(in: pipRect)
        }
        
        return combinedImage
    }
}

