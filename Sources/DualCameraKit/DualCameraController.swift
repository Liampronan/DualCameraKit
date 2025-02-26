import UIKit

/// Central camera controller
public final class DualCameraController {
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
    private var renderers: [CameraSource: CameraRenderer] = [:]
    private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    public init() {}
    
    public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.frontCameraStream
    }
    
    public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.backCameraStream
    }
    
    @MainActor
    public func startSession() async throws {
        try await streamSource.startSession()
        // Optionally, auto-initialize renderers for both sources here.
        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }
    
    public func stopSession() {
        streamSource.stopSession()
        cancelRendererTasks()
    }
    
    /// Creates a renderer (using MetalCameraRenderer by default).
    @MainActor
    public func createRenderer() -> CameraRenderer {
        return MetalCameraRenderer()
    }
    
    /// Returns a renderer for the specified camera source.
    /// If one does not exist yet, it is created and connected to its stream.
    @MainActor
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
    @MainActor
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
    
    // Example capture methods:
    
    /// Captures a photo using a designated primary renderer.
    public func capturePhoto() async throws -> UIImage {
        // Choose one renderer as the primary (here we assume back).
        guard let primaryRenderer = renderers[.back] else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        return try await primaryRenderer.captureCurrentFrame()
    }
    
    /// Combines photos from both renderers (for a PiP effect).
    public func captureCombinedPhoto() async throws -> UIImage {
        guard let frontRenderer = renderers[.front],
              let backRenderer = renderers[.back] else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        let backImage = try await backRenderer.captureCurrentFrame()
        let frontImage = try await frontRenderer.captureCurrentFrame()
        let size = backImage.size
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Draw full-screen back image.
            backImage.draw(in: CGRect(origin: .zero, size: size))
            // Overlay front image as picture-in-picture.
            let pipWidth = size.width / 3
            let pipHeight = size.height / 3
            let pipRect = CGRect(x: size.width - pipWidth - 10, y: 10, width: pipWidth, height: pipHeight)
            frontImage.draw(in: pipRect)
        }
    }
}

