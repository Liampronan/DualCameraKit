import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControlling {
    var frontCameraStream: AsyncStream<PixelBufferWrapper> { get }
    var backCameraStream: AsyncStream<PixelBufferWrapper> { get }
    func getRenderer(for source: CameraSource) -> CameraRenderer
    
    func startSession() async throws
    func stopSession()
    
    var photoCapturer: DualCameraPhotoCapturing { get }
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraCaptureMode) async throws -> UIImage
    
    var videoRecorder: DualCameraVideoRecording { get }
    func startVideoRecording() async throws
    func stopVideoRecording() async throws -> URL
}

// default implementations for `DualCameraVideoRecorder` - proxy to implementation in `videoRecorder`
extension DualCameraControlling {
    public func stopVideoRecording() async throws -> URL {
        try await videoRecorder.stopVideoRecording()
    }
    
    public func startVideoRecording() async throws {
        // Delegate to the underlying implementation
        try await videoRecorder.startVideoRecording()
    }
}

// default implementations for `DualCameraPhotoCapturing` - proxy to implementation in `photoCapturer`
public extension DualCameraControlling {
    public func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        try await photoCapturer.captureCurrentScreen(mode: mode)
    }
    
    public func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        let frontRenderer = getRenderer(for: .front)
        let backRenderer = getRenderer(for: .back)
        
        return try await photoCapturer.captureRawPhotos(frontRenderer: frontRenderer, backRenderer: backRenderer)
    }
}

@MainActor
public final class DualCameraController: DualCameraControlling {
    // TODO: can these be private(set)
    public var photoCapturer: any DualCameraPhotoCapturing
    
    public var videoRecorder: any DualCameraVideoRecording
    public var renderers: [CameraSource: CameraRenderer] = [:]
    
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
    
    private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    // MARK: - Video Recording Properties
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    public init(videoRecorder: any DualCameraVideoRecording, photoCapturer: any DualCameraPhotoCapturing) {
        self.videoRecorder = videoRecorder
        self.photoCapturer = photoCapturer
        
    }
    
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
}
