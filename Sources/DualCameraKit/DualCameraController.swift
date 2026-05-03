import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControlling {
    func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper>
    func getRenderer(for source: DualCameraSource) -> CameraRenderer
    func startSession() async throws
    func stopSession()

    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize) async throws -> UIImage

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws
}

@MainActor
public final class DualCameraController: DualCameraControlling {
    private let photoCapturer: any DualCameraPhotoCapturing
    private let streamSource: DualCameraCameraStreamSourcing

    private var renderers: [DualCameraSource: CameraRenderer] = [:]
    private var streamTasks: [DualCameraSource: Task<Void, Never>] = [:]

    public init(
        photoCapturer: (any DualCameraPhotoCapturing)? = nil,
        streamSource: DualCameraCameraStreamSourcing? = nil
    ) {
        self.photoCapturer = photoCapturer ?? DualCameraPhotoCapturer()
        self.streamSource = streamSource ?? DualCameraCameraStreamSource()
    }

    public func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        streamSource.subscribe(to: source)
    }

    public func startSession() async throws {
        try await streamSource.startSession()
        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }

    public func stopSession() {
        streamSource.stopSession()
        cancelRendererTasks()
        renderers.removeAll()
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        try streamSource.setTorchMode(mode)
    }

    public func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        let buffers = try latestBuffers()
        return try await photoCapturer.captureRawPhotos(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer
        )
    }

    public func capturePhoto(layout: DualCameraLayout, outputSize: CGSize) async throws -> UIImage {
        let buffers = try latestBuffers()
        return try await photoCapturer.captureComposedPhoto(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer,
            layout: layout,
            outputSize: outputSize
        )
    }

    public func createRenderer() -> CameraRenderer {
        MetalCameraRenderer()
    }

    public func getRenderer(for source: DualCameraSource) -> CameraRenderer {
        if let renderer = renderers[source] {
            return renderer
        }

        let renderer = createRenderer()
        renderers[source] = renderer
        connectStream(for: source, renderer: renderer)
        return renderer
    }

    private func latestBuffers() throws -> (front: PixelBufferWrapper, back: PixelBufferWrapper) {
        guard let front = streamSource.latestFrame(for: .front),
              let back = streamSource.latestFrame(for: .back) else {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        return (front, back)
    }

    private func connectStream(for source: DualCameraSource, renderer: CameraRenderer) {
        let stream = subscribe(to: source)
        let task = Task { @MainActor in
            for await buffer in stream {
                if Task.isCancelled { break }
                renderer.update(with: buffer.buffer)
            }
        }
        streamTasks[source] = task
    }

    private func cancelRendererTasks() {
        for task in streamTasks.values {
            task.cancel()
        }
        streamTasks.removeAll()
    }
}
