import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject, Sendable  {
    func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage
}

/// Determines the capture mode for photo screenshots.
///
/// - `fullScreen`: Captures the entire screen
/// - `containerFrame`: Captures only the specified frame region (used for container mode)
public enum DualCameraPhotoCaptureMode: Sendable, Equatable {
    case fullScreen
    /// Captures a specific rectangular region of the screen in global window coordinates.
    /// The frame's origin determines the top-left corner to start capturing from,
    /// and the size determines the dimensions of the captured area.
    case containerFrame(CGRect)

    @available(*, deprecated, message: "Use containerFrame instead")
    public static func containerSize(_ size: CGSize) -> DualCameraPhotoCaptureMode {
        .containerFrame(CGRect(origin: .zero, size: size))
    }
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
            
        case .containerFrame(let frame):
            guard !frame.size.width.isZero && !frame.size.height.isZero else {
                throw DualCameraError.captureFailure(.unknownDimensions)
            }


            let format = UIGraphicsImageRendererFormat()
            format.scale = screenScale
            format.opaque = true

            // Create renderer with optimized format for container size
            let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)

            // Generate cropped image by translating the drawing context
            let capturedImage = renderer.image { context in
                let cgContext = context.cgContext

                // Translate the context to "shift" the window so the desired frame is at origin
                cgContext.translateBy(x: -frame.origin.x, y: -frame.origin.y)

                // Draw the full window hierarchy, but only the translated portion will be visible
                keyWindow.drawHierarchy(
                    in: CGRect(origin: .zero, size: fullScreenSize),
                    afterScreenUpdates: afterScreenUpdates
                )
            }

            return capturedImage
        }
    }
}
