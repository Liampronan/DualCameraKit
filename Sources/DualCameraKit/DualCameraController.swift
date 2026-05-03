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
    private var sessionUseCount = 0
    private var isSessionStarted = false
    private var startSessionTask: Task<Void, Error>?
    private var scheduledStopTask: Task<Void, Never>?

    public init(
        photoCapturer: (any DualCameraPhotoCapturing)? = nil,
        streamSource: DualCameraCameraStreamSourcing? = nil
    ) {
        self.photoCapturer = photoCapturer ?? DualCameraPhotoCapturer()
        self.streamSource = streamSource ?? DualCameraCameraStreamSource()
    }

    deinit {
        scheduledStopTask?.cancel()
        for task in streamTasks.values {
            task.cancel()
        }
    }

    public func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        streamSource.subscribe(to: source)
    }

    public func startSession() async throws {
        cancelScheduledStop()
        sessionUseCount += 1

        do {
            try await ensureSessionStarted()
        } catch {
            sessionUseCount = max(0, sessionUseCount - 1)
            throw error
        }

        guard sessionUseCount > 0 else {
            stopSessionIfUnused()
            return
        }

        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }

    public func stopSession() {
        guard sessionUseCount > 0 else {
            stopSessionIfUnused()
            return
        }

        sessionUseCount -= 1
        stopSessionIfUnused()
    }

    private func stopSessionIfUnused() {
        guard sessionUseCount == 0 else { return }
        guard scheduledStopTask == nil else { return }

        scheduledStopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.stopSessionNowIfUnused()
            }
        }
    }

    private func cancelScheduledStop() {
        scheduledStopTask?.cancel()
        scheduledStopTask = nil
    }

    private func stopSessionNowIfUnused() {
        scheduledStopTask = nil
        guard sessionUseCount == 0 else { return }

        streamSource.stopSession()
        isSessionStarted = false
        startSessionTask?.cancel()
        startSessionTask = nil
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

    private func ensureSessionStarted() async throws {
        if isSessionStarted {
            return
        }

        if let startSessionTask {
            try await startSessionTask.value
            return
        }

        let task = Task { @MainActor in
            try await streamSource.startSession()
        }
        startSessionTask = task

        do {
            try await task.value
            isSessionStarted = true
            startSessionTask = nil
        } catch {
            startSessionTask = nil
            throw error
        }
    }

}
