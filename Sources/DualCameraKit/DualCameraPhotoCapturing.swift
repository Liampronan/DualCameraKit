import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject  {
    func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraCaptureMode) async throws -> UIImage
}

/// determines whether the photos are captured in as if displayed in `fullScreen` or in a layout not fillingl the fullscreen aka a container via `containerSize`
public enum DualCameraCaptureMode: Sendable {
    case fullScreen
    case containerSize(CGSize)
}

//@MainActor
// TODO: fixme sendable if this approach improves perf
public class DualCameraPhotoCapturer: DualCameraPhotoCapturing, @unchecked Sendable {
    
    public init() { }
    
    /// Captures raw photos from both cameras without any compositing
    public func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage) {
        // Capture front camera image
        let frontImage = try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<UIImage, Error>) in
            Task {
                do {
                    let image = try await frontRenderer.captureCurrentFrame()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Capture back camera image
        let backImage = try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<UIImage, Error>) in
            Task {
                do {
                    let image = try await backRenderer.captureCurrentFrame()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return (front: frontImage, back: backImage)
    }

    /// Captures the current screen content with improved performance.
    @MainActor
    public func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        // Cache UIApplication.shared to avoid multiple accesses
        let application = UIApplication.shared
        
        // Find the key window with optimized search
        guard let keyWindow = application.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }),
              let windowScene = keyWindow.windowScene else {
            throw DualCameraError.captureFailure(.screenCaptureUnavailable)
        }
        
        // Cache the screen size to avoid recalculation
        let fullScreenSize = windowScene.screen.bounds.size
        
        // Use afterScreenUpdates strategically to balance performance and visual quality
        // Setting to false improves performance but may capture incomplete UI in some cases
        let afterScreenUpdates = false // Better performance, might miss some UI updates
        
        switch mode {
        case .fullScreen:
            // Use optimized format for performance
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0 // Use exact pixel dimensions, not device scale
            format.opaque = true // Optimize for opaque content (no transparency)
            
            // Create renderer with optimized format
            let renderer = UIGraphicsImageRenderer(size: fullScreenSize, format: format)
            
            // Generate image with optimized settings
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
            
            // Use optimized format for container size too
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            
            // Create renderer with optimized format for container size
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            
            // Generate scaled image with optimized drawing
            let capturedImage = renderer.image { context in
                let cgContext = context.cgContext
                
                // Calculate scaling but use more efficient method
                let scaleX = size.width / fullScreenSize.width
                let scaleY = size.height / fullScreenSize.height
                let scale = min(scaleX, scaleY)
                
                // Apply scaling with optimized transform
                cgContext.scaleBy(x: scale, y: scale)
                
                // Draw with optimal parameters
                keyWindow.drawHierarchy(
                    in: CGRect(origin: .zero, size: fullScreenSize),
                    afterScreenUpdates: afterScreenUpdates
                )
            }
            return capturedImage
        }
    }
}
