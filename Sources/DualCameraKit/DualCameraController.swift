import UIKit
import SwiftUI

@MainActor
public protocol DualCameraControllerProtocol {
    var frontCameraStream: AsyncStream<PixelBufferWrapper> { get }
    var backCameraStream: AsyncStream<PixelBufferWrapper> { get }
    func startSession() async throws
    func stopSession()
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraCaptureMode) async throws -> UIImage
}

public extension DualCameraControllerProtocol {
    func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        try await captureCurrentScreen(mode: mode)
    }
}

public enum DualCameraCaptureMode {
    case fullScreen
    case containerSize(CGSize)
}

@MainActor
public final class DualCameraController: DualCameraControllerProtocol {
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
    private var renderers: [CameraSource: CameraRenderer] = [:]
    private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    public init() {}
    
    nonisolated public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.frontCameraStream
    }
    
    nonisolated public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.backCameraStream
    }
    
    public func startSession() async throws {
        try await streamSource.startSession()
        
        // Auto-initialize renderers
        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }
    
    public func stopSession() {
        streamSource.stopSession()
        cancelRendererTasks()
    }
    
    /// Creates a renderer (using MetalCameraRenderer by default).
    public func createRenderer() -> CameraRenderer {
        return MetalCameraRenderer()
    }
    
    /// Returns a renderer for the specified camera source.
    /// If one does not exist yet, it is created and connected to its stream.
    public func getRenderer(for source: CameraSource) -> CameraRenderer {
        if let renderer = renderers[source] {
            return renderer
        }
        
        let newRenderer = createRenderer()
        renderers[source] = newRenderer
        connectStream(for: source, renderer: newRenderer)
        return newRenderer
    }
    
    /// Connects the appropriate camera stream to the given renderer.
    private func connectStream(for source: CameraSource, renderer: CameraRenderer) {
        let stream: AsyncStream<PixelBufferWrapper> = source == .front ? frontCameraStream : backCameraStream
        // Create a task that forwards frames from the stream to the renderer.
        let task = Task {
            for await buffer in stream {
                if Task.isCancelled { break }
                await renderer.update(with: buffer.buffer)
            }
        }
        streamTasks[source] = task
    }
    
    /// Cancels all active stream tasks.
    private func cancelRendererTasks() {
        for task in streamTasks.values {
            task.cancel()
        }
        streamTasks.removeAll()
    }
    
    /// Captures raw photos from both cameras without any compositing
    public func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        guard let frontRenderer = renderers[.front],
              let backRenderer = renderers[.back] else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
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
    /// For now, we have an implicit dependency here on UIApplication for getting the keyWindow's windowScene.
    /// In the future that might make sense to extract
    public func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        // Give SwiftUI a moment to fully render
        try await Task.sleep(for: .milliseconds(50))
        
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
