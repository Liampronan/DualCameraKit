// swiftlint:disable file_length
import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControlling {
    func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper>
    func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent>
    func getRenderer(for source: DualCameraSource) -> CameraRenderer
    func startSession() async throws
    func stopSession()

    func captureRawPhotos(displayScale: CGFloat) async throws -> (front: UIImage, back: UIImage)
    /// Captures a composed photo for the given layout, output size, and display scale.
    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize, displayScale: CGFloat) async throws -> UIImage
    /// Captures a composed photo with an explicit content mode.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage
    /// Captures a composed photo with an explicit content mode and safe-area/overlay insets.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage

    /// Captures raw front/back images and a composed photo from a single synchronized frame pair.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet

    func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities
    @discardableResult
    func applyTorchMode(_ mode: AVCaptureDevice.TorchMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult
    @discardableResult
    func applyFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyWhiteBalanceMode(_ mode: AVCaptureDevice.WhiteBalanceMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult

    func diagnosticsSnapshot() -> DualCameraDiagnostics
}

public extension DualCameraControlling {
    /// Captures the latest front and back camera frames at scale `1`.
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        try await captureRawPhotos(displayScale: 1)
    }

    /// Captures a composed photo for `layout` and `outputSize` at scale `1`.
    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize) async throws -> UIImage {
        try await capturePhoto(layout: layout, outputSize: outputSize, displayScale: 1)
    }

    /// Captures a composed photo for `layout`, `outputSize`, and `overlayInsets` using `.aspectFill` at scale `1`.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: overlayInsets
        )
    }

    /// Captures a composed photo for `layout`, `outputSize`, and `contentMode` at scale `1`.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: contentMode,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a composed photo for `layout`, `outputSize`, `contentMode`, and `overlayInsets` at scale `1`.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        )
    }

    /// Captures a composed photo for `layout`, `outputSize`, and `displayScale` using `.aspectFill`.
    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize, displayScale: CGFloat) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a composed photo for `layout`, `outputSize`, `displayScale`, and `contentMode` with zero insets.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a composed photo for `layout`, `outputSize`, `displayScale`, and `overlayInsets` using `.aspectFill`.
    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        try await capturePhoto(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: overlayInsets
        )
    }

    /// Captures a photo set for `layout` and `outputSize` at scale `1` using `.aspectFill`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, and `overlayInsets` using `.aspectFill` at scale `1`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: overlayInsets
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, and `contentMode` at scale `1`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        contentMode: DualCameraContentMode
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: contentMode,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, `contentMode`, and `overlayInsets` at scale `1`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, and `displayScale` using `.aspectFill`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, `displayScale`, and `contentMode` with zero insets.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, `displayScale`, and `overlayInsets` using `.aspectFill`.
    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: overlayInsets
        )
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
    private var diagnosticEventHandler: DualCameraDiagnosticEventHandler?

    private var renderers: [DualCameraSource: CameraRenderer] = [:]
    private var streamTasks: [DualCameraSource: Task<Void, Never>] = [:]
    private var diagnosticEventTask: Task<Void, Never>?
    private var sessionUseCount = 0
    private var isSessionStarted = false
    private var stopGeneration: UInt64 = 0
    private var startSessionTask: Task<Void, Error>?
    private var scheduledStopTask: Task<Void, Never>?

    public init(
        photoCapturer: (any DualCameraPhotoCapturing)? = nil,
        streamSource: DualCameraCameraStreamSourcing? = nil,
        sessionStopDelay: Duration? = nil,
        sessionStopSleeper: (@MainActor @Sendable (Duration) async -> Void)? = nil,
        diagnosticEventHandler: DualCameraDiagnosticEventHandler? = nil
    ) {
        self.photoCapturer = photoCapturer ?? DualCameraPhotoCapturer()
        self.streamSource = streamSource ?? DualCameraCameraStreamSource()
        self.sessionStopDelay = sessionStopDelay ?? Self.navigationHandoffStopDelay
        self.diagnosticEventHandler = diagnosticEventHandler
        self.sleepBeforeSessionStop = sessionStopSleeper ?? { duration in
            do {
                try await Task.sleep(for: duration)
            } catch {}
        }
        startDiagnosticEventForwardingIfNeeded()
    }

    deinit {
        scheduledStopTask?.cancel()
        diagnosticEventTask?.cancel()
        for task in streamTasks.values {
            task.cancel()
        }
    }

    public func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        streamSource.subscribe(to: source)
    }

    public func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        streamSource.diagnosticEvents()
    }

    public func setDiagnosticEventHandler(_ handler: DualCameraDiagnosticEventHandler?) {
        diagnosticEventHandler = handler
        startDiagnosticEventForwardingIfNeeded()
    }

    /// Starts the dual-camera session or retains an active session across overlapping consumers.
    public func startSession() async throws {
        cancelScheduledStop()
        sessionUseCount += 1
        let stopGenerationAtStart = stopGeneration

        do {
            try await ensureSessionStarted(expectedStopGeneration: stopGenerationAtStart)
        } catch {
            if stopGeneration == stopGenerationAtStart {
                sessionUseCount = max(0, sessionUseCount - 1)
            }
            throw error
        }

        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }

    /// Releases one active consumer and schedules session teardown once no consumers remain.
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

        stopGeneration &+= 1
        streamSource.stopSession()
        isSessionStarted = false
        // If the only user disappears before the initial start finishes,
        // cancel the in-flight start so the hardware request does not outlive
        // the screen that needed it.
        startSessionTask?.cancel()
        startSessionTask = nil
    }

    public func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities {
        try streamSource.cameraCapabilities(for: source)
    }

    @discardableResult
    public func applyTorchMode(
        _ mode: AVCaptureDevice.TorchMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        try streamSource.applyTorchMode(mode, for: source)
    }

    @discardableResult
    public func applyZoomFactor(
        _ factor: CGFloat,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        try streamSource.applyZoomFactor(factor, for: source)
    }

    @discardableResult
    public func applyFocusMode(
        _ mode: AVCaptureDevice.FocusMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        try streamSource.applyFocusMode(mode, for: source)
    }

    @discardableResult
    public func applyExposureMode(
        _ mode: AVCaptureDevice.ExposureMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        try streamSource.applyExposureMode(mode, for: source)
    }

    @discardableResult
    public func applyWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        try streamSource.applyWhiteBalanceMode(mode, for: source)
    }

    public func diagnosticsSnapshot() -> DualCameraDiagnostics {
        streamSource.diagnosticsSnapshot()
    }

    public func captureRawPhotos(displayScale: CGFloat) async throws -> (front: UIImage, back: UIImage) {
        let buffers = try latestFramePair()
        return try await photoCapturer.captureRawPhotos(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer,
            displayScale: displayScale
        )
    }

    /// Captures and composites the latest front and back camera frames using `layout` and `overlayInsets`.
    public func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets = EdgeInsets()
    ) async throws -> UIImage {
        try await capturePhotoSet(
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        ).composed
    }

    /// Captures raw front/back images and composites the latest front and back camera frames from a single frame pair.
    public func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets = EdgeInsets()
    ) async throws -> DualCameraCapturedPhotoSet {
        let buffers = try latestFramePair()
        return try await photoCapturer.capturePhotoSet(
            frontBuffer: buffers.front.buffer,
            backBuffer: buffers.back.buffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: overlayInsets
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

    private func connectStream(for source: DualCameraSource, renderer: CameraRenderer) {
        let stream = subscribe(to: source)
        let task = Task {
            for await buffer in stream {
                if Task.isCancelled { break }
                renderer.update(with: buffer)
            }
        }
        streamTasks[source] = task
    }

    private func startDiagnosticEventForwardingIfNeeded() {
        guard diagnosticEventHandler != nil else {
            diagnosticEventTask?.cancel()
            diagnosticEventTask = nil
            return
        }
        guard diagnosticEventTask == nil else { return }

        let eventStream = streamSource.diagnosticEvents()
        diagnosticEventTask = Task { [weak self] in
            for await event in eventStream {
                guard !Task.isCancelled else { break }
                await self?.diagnosticEventHandler?(event)
            }
        }
    }

    private func ensureSessionStarted(expectedStopGeneration: UInt64) async throws {
        if isSessionStarted {
            return
        }

        if let startSessionTask {
            try await startSessionTask.value
            guard stopGeneration == expectedStopGeneration, isSessionStarted else {
                throw CancellationError()
            }
            return
        }

        let task = Task { @MainActor in
            try await streamSource.startSession()
        }
        startSessionTask = task

        do {
            try await task.value
            guard stopGeneration == expectedStopGeneration else {
                throw CancellationError()
            }
            isSessionStarted = true
            startSessionTask = nil
        } catch {
            if stopGeneration == expectedStopGeneration {
                startSessionTask = nil
            }
            throw error
        }
    }

}

// MARK: - Frame pair selection

extension DualCameraController {
    /// Frame pairs older than this, relative to the newest single-camera frame, count as stale.
    static let framePairFreshnessTolerance = CMTime(value: 1, timescale: 10)
    /// Fallback frames further apart than this are reported, since one camera may have stalled.
    static let fallbackFrameGapTolerance = CMTime(value: 1, timescale: 10)

    fileprivate func latestFramePair() throws -> DualCameraFramePair {
        let front = streamSource.latestFrame(for: .front)
        let back = streamSource.latestFrame(for: .back)
        let synchronizedPair = streamSource.latestFramePair()

        if let synchronizedPair, Self.isFresh(synchronizedPair, comparedTo: [front, back]) {
            return synchronizedPair
        }

        // The front and back cameras are not hardware-synchronized, so the output synchronizer can go
        // long stretches (or a whole session) without delivering both frames in one collection.
        // Fall back to the newest frame from each camera; they may be a few milliseconds apart.
        if let front, let back {
            let timestamps = [front.presentationTimestamp, back.presentationTimestamp].compactMap { $0 }
            recordFallbackCapture(front: front, back: back)
            return DualCameraFramePair(front: front, back: back, timestamp: timestamps.min())
        }

        if let synchronizedPair {
            return synchronizedPair
        }

        throw DualCameraError.captureFailure(.noFrameAvailable)
    }

    private func recordFallbackCapture(front: PixelBufferWrapper, back: PixelBufferWrapper) {
        let frameGap = Self.frameGap(between: front, and: back)
        let exceedsTolerance = frameGap.map { $0 > Self.fallbackFrameGapTolerance } ?? false

        streamSource.recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: exceedsTolerance ? .captureFrameGapExceeded : .captureUsedFallbackFrames,
                context: .captureFallback(frameGapSeconds: frameGap?.seconds)
            )
        )
    }

    static func frameGap(between front: PixelBufferWrapper, and back: PixelBufferWrapper) -> CMTime? {
        guard let frontTimestamp = front.presentationTimestamp, frontTimestamp.isNumeric,
              let backTimestamp = back.presentationTimestamp, backTimestamp.isNumeric else {
            return nil
        }

        return CMTimeAbsoluteValue(frontTimestamp - backTimestamp)
    }

    static func isFresh(_ framePair: DualCameraFramePair, comparedTo frames: [PixelBufferWrapper?]) -> Bool {
        guard let pairTimestamp = framePair.timestamp, pairTimestamp.isNumeric else {
            return true
        }

        let newestFrameTimestamp = frames
            .compactMap { $0?.presentationTimestamp }
            .filter(\.isNumeric)
            .max()

        guard let newestFrameTimestamp else {
            return true
        }

        return newestFrameTimestamp - pairTimestamp <= framePairFreshnessTolerance
    }
}
