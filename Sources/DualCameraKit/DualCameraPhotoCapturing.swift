import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject {
    func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraCaptureMode) async throws -> UIImage
}

/// determines whether the photos are captured in as if displayed in `fullScreen` or in a layout not fillingl the fullscreen aka a container via `containerSize`
public enum DualCameraCaptureMode {
    case fullScreen
    case containerSize(CGSize)
}

@MainActor
public class DualCameraPhotoCapturer: DualCameraPhotoCapturing {
    
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

    /// Captures the current screen content.
    public func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        // TODO: I think we can remove this  Give SwiftUI a moment to fully render
//        try await Task.sleep(for: .milliseconds(50))
        
        // First try to find the app's key window (works with both UIKit and SwiftUI)
        guard let keyWindow = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }),
                let windowScene = keyWindow.windowScene else {
            throw DualCameraError.captureFailure(.screenCaptureUnavailable)
        }
        
        // Get scene size (full screen including safe areas)
        let fullScreenSize = windowScene.screen.bounds.size
        
        switch mode {
        case .fullScreen:
            // Use full screen size for rendering
            let renderer = UIGraphicsImageRenderer(size: fullScreenSize)
            let capturedImage = renderer.image { _ in
                keyWindow.drawHierarchy(in: CGRect(origin: .zero, size: fullScreenSize), afterScreenUpdates: true)
            }
            return capturedImage
            
        case .containerSize(let size):
            guard !size.width.isZero && !size.height.isZero else {
                throw DualCameraError.captureFailure(.unknownDimensions)
            }
            
            // Use the container size for rendering
            let renderer = UIGraphicsImageRenderer(size: size)
            let capturedImage = renderer.image { context in
                // Calculate scaling to make the full screen content fit within the container size
                let scaleX = size.width / fullScreenSize.width
                let scaleY = size.height / fullScreenSize.height
                let scale = min(scaleX, scaleY) // Use min to fit the entire screen
                
                // Apply scaling
                context.cgContext.scaleBy(x: scale, y: scale)
                
                // Draw the hierarchy scaled to fit
                keyWindow.drawHierarchy(in: CGRect(origin: .zero, size: CGSize(
                    width: fullScreenSize.width,
                    height: fullScreenSize.height
                )), afterScreenUpdates: true)
            }
            return capturedImage
        }
    }
}
