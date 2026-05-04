import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControlling {
    func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper>
    func getRenderer(for source: DualCameraSource) -> CameraRenderer
    func startSession() async throws
    func stopSession()

    func captureRawPhotos(displayScale: CGFloat) async throws -> (front: UIImage, back: UIImage)
    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize, displayScale: CGFloat) async throws -> UIImage

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws
}

public extension DualCameraControlling {
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        try await captureRawPhotos(displayScale: 1)
    }

    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize) async throws -> UIImage {
        try await capturePhoto(layout: layout, outputSize: outputSize, displayScale: 1)
    }
}

@MainActor
public final class DualCameraController: DualCameraControlling {
    // SwiftUI can briefly overlap outgoing and incoming camera screens during
    // animated navigation/demo handoffs. Keep the capture session alive across
    // that small gap so transitions do not tear down and restart camera capture.
    private static let navigationHandoffStopDelay: Duration = .milliseconds(450)

    private let photoCapturer: any DualCameraPhotoCapturing
    private let streamSource: DualCameraCameraStreamSourcing
    private let sessionStopDelay: Duration
    private let sleepBeforeSessionStop: @MainActor @Sendable (Duration) async -> Void

    private var renderers: [DualCameraSource: CameraRenderer] = [:]
    private var streamTasks: [DualCameraSource: Task<Void, Never>] = [:]
    private var sessionUseCount = 0
    private var isSessionStarted = false
    private var startSessionTask: Task<Void, Error>?
    private var scheduledStopTask: Task<Void, Never>?

    public init(
        photoCapturer: (any DualCameraPhotoCapturing)? = nil,
        streamSource: DualCameraCameraStreamSourcing? = nil,
        sessionStopDelay: Duration? = nil,
        sessionStopSleeper: (@MainActor @Sendable (Duration) async -> Void)? = nil
    ) {
        self.photoCapturer = photoCapturer ?? DualCameraPhotoCapturer()
        self.streamSource = streamSource ?? DualCameraCameraStreamSource()
        self.sessionStopDelay = sessionStopDelay ?? Self.navigationHandoffStopDelay
        self.sleepBeforeSessionStop = sessionStopSleeper ?? { duration in
            do {
                try await Task.sleep(for: duration)
            } catch {}
        }
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

        let sessionStopDelay = sessionStopDelay
        let sleepBeforeSessionStop = sleepBeforeSessionStop
        scheduledStopTask = Task { [weak self] in
            await sleepBeforeSessionStop(sessionStopDelay)
            guard !Task.isCancelled else { return }

            self?.stopSessionNowIfUnused()
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
        // If the only user disappears before the initial start finishes,
        // cancel the in-flight start so the hardware request does not outlive
        // the screen that needed it.
        startSessionTask?.cancel()
        startSessionTask = nil
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        try streamSource.setTorchMode(mode)
    }

    public func captureRawPhotos(displayScale: CGFloat) async throws -> (front: UIImage, back: UIImage) {
        let buffers = try latestBuffers()
        return try await photoCapturer.captureRawPhotos(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer,
            displayScale: displayScale
        )
    }

    public func capturePhoto(layout: DualCameraLayout, outputSize: CGSize, displayScale: CGFloat) async throws -> UIImage {
        let buffers = try latestBuffers()
        return try await photoCapturer.captureComposedPhoto(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale
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
