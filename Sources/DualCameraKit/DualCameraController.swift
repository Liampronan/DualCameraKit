import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControlling {
    var frontCameraStream: AsyncStream<PixelBufferWrapper> { get }
    var backCameraStream: AsyncStream<PixelBufferWrapper> { get }
    func getRenderer(for source: DualCameraSource) -> CameraRenderer
    func startSession() async throws
    func stopSession()

    var photoCapturer: any DualCameraPhotoCapturing { get }
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage

    // NEW: Stream-based capture with layout composition
    func captureComposedPhoto(layout: DualCameraLayout, mode: DualCameraPhotoCaptureMode) async throws -> UIImage

    // Ideally we could remove the need for `photoCapturer` and `videoRecorder` to be public.
    // We only are accessing them from inside this file - one videoRecorder type requires access to the `photoCapturer` which we do in the extension.
    // Probably more decoupling would help but not focused on that atm.
    var videoRecorder: (any DualCameraVideoRecording)? { get }
    func setVideoRecorder(_ recorder: any DualCameraVideoRecording) async throws
    func startVideoRecording(mode: DualCameraVideoRecordingMode) async throws
    func stopVideoRecording() async throws -> URL

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode, for camera: DualCameraSource) throws
}

// default implementations for `DualCameraVideoRecorder` - proxy to implementation in `videoRecorder`
extension DualCameraControlling {
    public func stopVideoRecording() async throws -> URL {
        guard let videoRecorder else {
            throw DualCameraError.recordingFailed(.noVideoRecorderSet)
        }
        return try await videoRecorder.stopVideoRecording()
    }
    
    public func startVideoRecording(mode: DualCameraVideoRecordingMode) async throws {
        let videoRecorder: any DualCameraVideoRecording = switch mode {
        case .replayKit(let config): DualCameraReplayKitVideoRecorder(config: config)
        case .cpuBased(let config): DualCameraCPUVideoRecorderManager(photoCapturer: photoCapturer, config: config)
        }
        try await setVideoRecorder(videoRecorder)

        try await videoRecorder.startVideoRecording()
    }
}

// default implementations for `DualCameraPhotoCapturing` - proxy to implementation in `photoCapturer`
public extension DualCameraControlling {
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode = .fullScreen) async throws -> UIImage {
        try await photoCapturer.captureCurrentScreen(mode: mode)
    }
    
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
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

    var renderers: [DualCameraSource: CameraRenderer] = [:]

    private let streamSource: DualCameraCameraStreamSourcing
    
    // Internal storage for renderers and their stream tasks.
    private var streamTasks: [DualCameraSource: Task<Void, Never>] = [:]

    // MARK: - Stream-based Capture
    private let streamPhotoCapturer: DualCameraStreamPhotoCapturer
    public let useStreamCapture: Bool

    // MARK: - Video Recording Properties

    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    public init(
        photoCapturer: any DualCameraPhotoCapturing = DualCameraPhotoCapturer(),
        useStreamCapture: Bool = false, // Default to legacy for backward compatibility
        photoStyle: DualCameraPhotoStyle = .dualCameraScreen,
        streamSource: DualCameraCameraStreamSourcing
    ) {
        self.photoCapturer = photoCapturer
        self.useStreamCapture = useStreamCapture
        self.streamPhotoCapturer = DualCameraStreamPhotoCapturer(style: photoStyle)
        self.streamSource = streamSource
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
        // Clear renderers so they're recreated with fresh stream connections on next startSession()
        renderers.removeAll()
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode, for camera: DualCameraSource) throws {
        try streamSource.setTorchMode(mode, for: camera)
    }

    /// Captures a composed photo using stream-based composition at native camera resolution
    public func captureComposedPhoto(layout: DualCameraLayout, mode: DualCameraPhotoCaptureMode) async throws -> UIImage {
        let frontRenderer = getRenderer(for: .front)
        let backRenderer = getRenderer(for: .back)

        // Calculate output size based on mode
        let outputSize = calculateOutputSize(for: mode)
        print("input outputsize is...", outputSize)
        return try await streamPhotoCapturer.captureComposedPhoto(
            frontRenderer: frontRenderer,
            backRenderer: backRenderer,
            layout: layout,
            outputSize: outputSize
        )
    }

    /// Helper to calculate output size from capture mode
    private func calculateOutputSize(for mode: DualCameraPhotoCaptureMode) -> CGSize {
        switch mode {
        case .fullScreen:
            // Use screen dimensions at native scale
            let screen = UIScreen.main
            return CGSize(
                width: screen.bounds.width * screen.scale,
                height: screen.bounds.height * screen.scale
            )
        case .containerFrame(let frame):
            // Use container dimensions at native scale
            let screen = UIScreen.main
            return CGSize(
                width: frame.width * screen.scale,
                height: frame.height * screen.scale
            )
        }
    }

    /// Creates a renderer (using MetalCameraRenderer by default).
    public func createRenderer() -> CameraRenderer {
        return MetalCameraRenderer()
    }
    
    /// Returns a renderer for the specified camera source.
    /// If one does not exist yet, it is created and connected to its stream.
    public func getRenderer(for source: DualCameraSource) -> CameraRenderer {
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
    private func connectStream(for source: DualCameraSource, renderer: CameraRenderer) {
        let stream: AsyncStream<PixelBufferWrapper> = source == .front ? frontCameraStream : backCameraStream
        // Create a task that forwards frames from the stream to the renderer.
        let task = Task {
            for await buffer in stream {
                if Task.isCancelled { break }
                renderer.update(with: buffer.buffer)
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


