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
    
    var photoCapturer: any DualCameraPhotoCapturing { get }
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage
    // Ideally we could remove the need for `photoCapturer` and `videoRecorder` to be public.
    // We only are accessing them from inside this file - one videoRecorder type requires access to the `photoCapturer` which we do in the extension.
    // Probably more decoupling would help but not focused on that atm.
    var videoRecorder: (any DualCameraVideoRecording)? { get }
    func setVideoRecorder(_ recorder: any DualCameraVideoRecording) async throws
    func startVideoRecording(recorderType: DualCameraVideoRecorderType) async throws
    func stopVideoRecording() async throws -> URL
}

protocol DualCameraControllerMutableVideoRecorder {
    var videoRecorder: (any DualCameraVideoRecording)? { get }
}

// default implementations for `DualCameraVideoRecorder` - proxy to implementation in `videoRecorder`
extension DualCameraControlling {
    public func stopVideoRecording() async throws -> URL {
        guard let videoRecorder else {
            throw DualCameraError.recordingFailed(.noVideoRecorderSet)
        }
        return try await videoRecorder.stopVideoRecording()
    }
    
    public func startVideoRecording(recorderType: DualCameraVideoRecorderType) async throws {
        let videoRecorder: any DualCameraVideoRecording = switch recorderType {
        case .replayKit(let config): DualCameraReplayKitVideoRecorder(config: config)
        case .cpuBased(let config): DualCameraCPUVideoRecorderManager(photoCapturer: photoCapturer, config: config)
        }
        try await setVideoRecorder(videoRecorder)

        try await videoRecorder.startVideoRecording()
    }
}

// default implementations for `DualCameraPhotoCapturing` - proxy to implementation in `photoCapturer`
public extension DualCameraControlling {
    public func captureCurrentScreen(mode: DualCameraPhotoCaptureMode = .fullScreen) async throws -> UIImage {
        try await photoCapturer.captureCurrentScreen(mode: mode)
    }
    
    public func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        let frontRenderer = getRenderer(for: .front)
        let backRenderer = getRenderer(for: .back)
        
        return try await photoCapturer.captureRawPhotos(frontRenderer: frontRenderer, backRenderer: backRenderer)
    }
}

public final class DualCameraController: DualCameraControlling {
    public var photoCapturer: any DualCameraPhotoCapturing
    // `videoRecorder` is optionally because
    // a) this controller may just be used to capture photos AND
    // b) this allows dynamic VideoRecorder creation at start of video capture (see startVideoRecording(recorderType:)
    public var videoRecorder: (any DualCameraVideoRecording)?
    
    var renderers: [CameraSource: CameraRenderer] = [:]
    
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
        private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    // MARK: - Video Recording Properties
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    public init(photoCapturer: any DualCameraPhotoCapturing = DualCameraPhotoCapturer()) {
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
    
    public func setVideoRecorder(_ recorder: any DualCameraVideoRecording) async throws {
        if let videoRecorder, await videoRecorder.isCurrentlyRecording {
            throw DualCameraError.recordingInProgress
        }
        self.videoRecorder = recorder
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
