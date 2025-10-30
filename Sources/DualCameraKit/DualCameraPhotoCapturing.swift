import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject, Sendable  {
    func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage
}

/// determines whether the photos are captured in as if displayed in `fullScreen` or in a layout not fillingl the fullscreen aka a container via `containerSize`
public enum DualCameraPhotoCaptureMode: Sendable, Equatable {
    case fullScreen
    case containerSize(CGSize)
}

public class DualCameraPhotoCapturer: DualCameraPhotoCapturing {
    
    public init() { }
    
    /// Captures raw photos from both cameras without any compositing.
    /// Returns both images but without any context of how they were laid out.
    ///
    /// APPROACH: Using concurrent tasks to capture both cameras as close to simultaneously as possible
    /// This schedules both capture operations to begin nearly at the same time, minimizing the temporal gap
    /// between frames compared to sequential capture.
    ///
    /// LIMITATION: While this approach significantly reduces the time between captures (typically to single-digit
    /// milliseconds), it doesn't guarantee perfect frame-level synchronization. True frame synchronization
    /// would require lower-level camera APIs like AVCaptureMultiCamSession or hardware-level synchronization.
    public func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage) {
        
        let frontTask = Task { try await frontRenderer.captureCurrentFrame() }
        let backTask = Task { try await backRenderer.captureCurrentFrame() }
        
        let frontImage = try await frontTask.value
        let backImage = try await backTask.value
        
        return (front: frontImage, back: backImage)
    }
    
    /// Captures the screen including any UI layout.
    /// Returns an image that is a screenshot of the screen.
    public func captureCurrentScreen(mode: DualCameraPhotoCaptureMode = .fullScreen) async throws -> UIImage {
        let application = UIApplication.shared
        guard let keyWindow = application.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }),
              let windowScene = keyWindow.windowScene else {
            throw DualCameraError.captureFailure(.screenCaptureUnavailable)
        }
        let screenScale = windowScene.screen.scale
        let fullScreenSize = windowScene.screen.bounds.size
        
        // Use afterScreenUpdates to balance performance and visual quality
        // Setting to false improves performance but may capture incomplete UI in some cases
        let afterScreenUpdates = false
        
        switch mode {
        case .fullScreen:
            let format = UIGraphicsImageRendererFormat()
            format.scale = screenScale
            format.opaque = true // Optimize for opaque content (no transparency)
            
            // Create renderer with optimized format
            let renderer = UIGraphicsImageRenderer(size: fullScreenSize, format: format)
            
            let capturedImage = renderer.image { _ in
                keyWindow.drawHierarchy(
                    in: CGRect(origin: .zero, size: fullScreenSize),
                    afterScreenUpdates: afterScreenUpdates
                )
            }
            return capturedImage
            
        case .containerSize(let size):
            guard !size.width.isZero && !size.height.isZero else {
                throw DualCameraError.captureFailure(.unknownDimensions)
            }
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = screenScale
            format.opaque = true
            
            // Create renderer with optimized format for container size
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            
            // Generate scaled image with optimized drawing
            let capturedImage = renderer.image { context in
                let cgContext = context.cgContext
                
                keyWindow.drawHierarchy(
                    in: CGRect(origin: .zero, size: fullScreenSize),
                    afterScreenUpdates: afterScreenUpdates
                )
            }
            return capturedImage
        }
    }
}
