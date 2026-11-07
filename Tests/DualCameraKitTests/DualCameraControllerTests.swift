// swiftlint:disable file_length
import AVFoundation
@testable import DualCameraKit
import SwiftUI
import XCTest

@MainActor
// swiftlint:disable:next type_body_length
final class DualCameraControllerTests: XCTestCase {
    func test_captureRawPhotosUsesSynchronizedFramePair() async throws {
        let streamSource = SpyCameraStreamSource()
        let expectedFront = try makePixelBuffer(color: .red)
        let expectedBack = try makePixelBuffer(color: .blue)
        streamSource.framePair = DualCameraFramePair(
            front: PixelBufferWrapper(buffer: expectedFront),
            back: PixelBufferWrapper(buffer: expectedBack)
        )
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(
            photoCapturer: photoCapturer,
            streamSource: streamSource
        )

        _ = try await controller.captureRawPhotos()

        XCTAssertTrue(photoCapturer.rawFrontBuffer === expectedFront)
        XCTAssertTrue(photoCapturer.rawBackBuffer === expectedBack)
    }

    func test_captureFallsBackToLatestFramesWithoutSynchronizedPair() async throws {
        let streamSource = SpyCameraStreamSource()
        let expectedFront = try makePixelBuffer(color: .red)
        let expectedBack = try makePixelBuffer(color: .blue)
        streamSource.frames = [
            .front: PixelBufferWrapper(buffer: expectedFront),
            .back: PixelBufferWrapper(buffer: expectedBack)
        ]
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(photoCapturer: photoCapturer, streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        XCTAssertTrue(photoCapturer.rawFrontBuffer === expectedFront)
        XCTAssertTrue(photoCapturer.rawBackBuffer === expectedBack)
    }

    func test_capturePrefersLatestFramesOverStaleSynchronizedPair() async throws {
        let streamSource = SpyCameraStreamSource()
        let staleFront = try makePixelBuffer(color: .green)
        let staleBack = try makePixelBuffer(color: .yellow)
        let expectedFront = try makePixelBuffer(color: .red)
        let expectedBack = try makePixelBuffer(color: .blue)
        streamSource.framePair = DualCameraFramePair(
            front: PixelBufferWrapper(buffer: staleFront),
            back: PixelBufferWrapper(buffer: staleBack),
            timestamp: CMTime(seconds: 1, preferredTimescale: 600)
        )
        streamSource.frames = [
            .front: PixelBufferWrapper(
                buffer: expectedFront,
                presentationTimestamp: CMTime(seconds: 5, preferredTimescale: 600)
            ),
            .back: PixelBufferWrapper(
                buffer: expectedBack,
                presentationTimestamp: CMTime(seconds: 5.01, preferredTimescale: 600)
            )
        ]
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(photoCapturer: photoCapturer, streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        XCTAssertTrue(photoCapturer.rawFrontBuffer === expectedFront)
        XCTAssertTrue(photoCapturer.rawBackBuffer === expectedBack)
    }

    func test_capturePrefersFreshSynchronizedPairOverLatestFrames() async throws {
        let streamSource = SpyCameraStreamSource()
        let expectedFront = try makePixelBuffer(color: .red)
        let expectedBack = try makePixelBuffer(color: .blue)
        streamSource.framePair = DualCameraFramePair(
            front: PixelBufferWrapper(buffer: expectedFront),
            back: PixelBufferWrapper(buffer: expectedBack),
            timestamp: CMTime(seconds: 5, preferredTimescale: 600)
        )
        streamSource.frames = [
            .front: PixelBufferWrapper(
                buffer: try makePixelBuffer(color: .green),
                presentationTimestamp: CMTime(seconds: 5.03, preferredTimescale: 600)
            ),
            .back: PixelBufferWrapper(
                buffer: try makePixelBuffer(color: .yellow),
                presentationTimestamp: CMTime(seconds: 5.02, preferredTimescale: 600)
            )
        ]
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(photoCapturer: photoCapturer, streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        XCTAssertTrue(photoCapturer.rawFrontBuffer === expectedFront)
        XCTAssertTrue(photoCapturer.rawBackBuffer === expectedBack)
    }

    func test_fallbackCaptureRecordsFrameGap() async throws {
        let streamSource = try makeStreamSourceWithFrames(frontSeconds: 5, backSeconds: 5.05)
        let controller = DualCameraController(photoCapturer: RecordingPhotoCapturer(), streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        let event = try XCTUnwrap(streamSource.recordedEvents.first)
        XCTAssertEqual(streamSource.recordedEvents.count, 1)
        XCTAssertEqual(event.kind, .captureUsedFallbackFrames)
        guard case .captureFallback(let frameGapSeconds) = event.context else {
            return XCTFail("Expected fallback context")
        }
        XCTAssertEqual(try XCTUnwrap(frameGapSeconds), 0.05, accuracy: 0.01)
    }

    func test_fallbackCaptureReportsOversizedFrameGap() async throws {
        let streamSource = try makeStreamSourceWithFrames(frontSeconds: 2, backSeconds: 5)
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(photoCapturer: photoCapturer, streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        XCTAssertEqual(streamSource.recordedEvents.map(\.kind), [.captureFrameGapExceeded])
        XCTAssertNotNil(photoCapturer.rawFrontBuffer)
    }

    func test_fallbackCaptureWithoutTimestampsRecordsUnknownFrameGap() async throws {
        let streamSource = SpyCameraStreamSource()
        streamSource.frames = [
            .front: PixelBufferWrapper(buffer: try makePixelBuffer(color: .red)),
            .back: PixelBufferWrapper(buffer: try makePixelBuffer(color: .blue))
        ]
        let controller = DualCameraController(photoCapturer: RecordingPhotoCapturer(), streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        let event = try XCTUnwrap(streamSource.recordedEvents.first)
        XCTAssertEqual(event.kind, .captureUsedFallbackFrames)
        XCTAssertEqual(event.context, .captureFallback(frameGapSeconds: nil))
    }

    func test_freshSynchronizedPairRecordsNoFallbackEvent() async throws {
        let streamSource = try makeStreamSourceWithFrames(frontSeconds: 5, backSeconds: 5.01)
        streamSource.framePair = DualCameraFramePair(
            front: PixelBufferWrapper(buffer: try makePixelBuffer(color: .red)),
            back: PixelBufferWrapper(buffer: try makePixelBuffer(color: .blue)),
            timestamp: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let controller = DualCameraController(photoCapturer: RecordingPhotoCapturer(), streamSource: streamSource)

        _ = try await controller.captureRawPhotos()

        XCTAssertTrue(streamSource.recordedEvents.isEmpty)
    }

    func test_mockStreamSourceCountsFallbackEventsInSnapshot() {
        let streamSource = DualCameraMockCameraStreamSource(animated: false)

        streamSource.recordDiagnosticEvent(DualCameraDiagnosticEvent(kind: .captureUsedFallbackFrames))
        streamSource.recordDiagnosticEvent(DualCameraDiagnosticEvent(kind: .captureFrameGapExceeded))

        let snapshot = streamSource.diagnosticsSnapshot()
        XCTAssertEqual(snapshot.captureFallbackCount, 2)
        XCTAssertEqual(snapshot.captureFrameGapExceededCount, 1)
    }

    func test_capturePhotoForwardsOverlayInsets() async throws {
        let streamSource = SpyCameraStreamSource()
        let buffer = try makePixelBuffer(color: .red)
        streamSource.framePair = DualCameraFramePair(
            front: PixelBufferWrapper(buffer: buffer),
            back: PixelBufferWrapper(buffer: buffer)
        )
        let photoCapturer = RecordingPhotoCapturer()
        let controller = DualCameraController(
            photoCapturer: photoCapturer,
            streamSource: streamSource
        )
        let insets = EdgeInsets(top: 44, leading: 12, bottom: 34, trailing: 12)

        _ = try await controller.capturePhoto(
            layout: .piP(miniCamera: .front, miniCameraPosition: .topLeading),
            outputSize: CGSize(width: 300, height: 600),
            overlayInsets: insets
        )

        XCTAssertEqual(photoCapturer.composedOverlayInsets, insets)
    }

    func test_streamSourceDefaultsToMirroringFrontCamera() {
        let defaultSource = DualCameraCameraStreamSource()
        XCTAssertTrue(defaultSource.mirrorsFrontCamera)

        let unmirroredSource = DualCameraCameraStreamSource(mirrorsFrontCamera: false)
        XCTAssertFalse(unmirroredSource.mirrorsFrontCamera)
    }

    func test_captureThrowsNoFrameAvailableWithoutAnyFrames() async throws {
        let controller = DualCameraController(
            photoCapturer: RecordingPhotoCapturer(),
            streamSource: SpyCameraStreamSource()
        )

        do {
            _ = try await controller.captureRawPhotos()
            XCTFail("Expected capture to throw")
        } catch {
            XCTAssertEqual(error as? DualCameraError, .captureFailure(.noFrameAvailable))
        }
    }

    private func makeStreamSourceWithFrames(
        frontSeconds: Double,
        backSeconds: Double
    ) throws -> SpyCameraStreamSource {
        let streamSource = SpyCameraStreamSource()
        streamSource.frames = [
            .front: PixelBufferWrapper(
                buffer: try makePixelBuffer(color: .red),
                presentationTimestamp: CMTime(seconds: frontSeconds, preferredTimescale: 600)
            ),
            .back: PixelBufferWrapper(
                buffer: try makePixelBuffer(color: .blue),
                presentationTimestamp: CMTime(seconds: backSeconds, preferredTimescale: 600)
            )
        ]
        return streamSource
    }

    func test_errorBridgesLocalizedDescription() {
        let error: Error = DualCameraError.captureFailure(.noFrameAvailable)

        XCTAssertEqual(error.localizedDescription, "No frame available to capture.")
        XCTAssertEqual((error as NSError).localizedDescription, "No frame available to capture.")
    }

    func test_stopSessionDebouncesDuringNavigationHandoff() async throws {
        let streamSource = SpyCameraStreamSource()
        let sleeper = ManualSessionStopSleeper()
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(50),
            sessionStopSleeper: { duration in
                await sleeper.sleep(for: duration)
            }
        )

        try await controller.startSession()
        controller.stopSession()
        await sleeper.waitForSleepRequests(1)

        try await controller.startSession()
        sleeper.finishNextSleep()
        await Task.yield()

        XCTAssertEqual(streamSource.startCount, 1)
        XCTAssertEqual(streamSource.stopCount, 0)

        controller.stopSession()
        await sleeper.waitForSleepRequests(2)
        sleeper.finishNextSleep()
        await streamSource.waitForStopCount(1)

        XCTAssertEqual(streamSource.stopCount, 1)
    }

    func test_stopSessionWaitsForAllActiveUsers() async throws {
        let streamSource = SpyCameraStreamSource()
        let sleeper = ManualSessionStopSleeper()
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(20),
            sessionStopSleeper: { duration in
                await sleeper.sleep(for: duration)
            }
        )

        try await controller.startSession()
        try await controller.startSession()

        controller.stopSession()
        await Task.yield()

        XCTAssertEqual(streamSource.stopCount, 0)
        XCTAssertEqual(sleeper.requestedDurations.count, 0)

        controller.stopSession()
        await sleeper.waitForSleepRequests(1)
        sleeper.finishNextSleep()
        await streamSource.waitForStopCount(1)

        XCTAssertEqual(streamSource.stopCount, 1)
    }

    func test_startSessionFailureReleasesUseCount() async throws {
        let streamSource = SpyCameraStreamSource()
        let sleeper = ManualSessionStopSleeper()
        streamSource.startError = DualCameraError.unknownError
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(20),
            sessionStopSleeper: { duration in
                await sleeper.sleep(for: duration)
            }
        )

        do {
            try await controller.startSession()
            XCTFail("Expected startSession to throw")
        } catch {
            XCTAssertEqual(error as? DualCameraError, .unknownError)
        }

        streamSource.startError = nil
        try await controller.startSession()
        controller.stopSession()
        await sleeper.waitForSleepRequests(1)
        sleeper.finishNextSleep()
        await streamSource.waitForStopCount(1)

        XCTAssertEqual(streamSource.startCount, 2)
        XCTAssertEqual(streamSource.stopCount, 1)
    }

    func test_sessionLifecycleRunnerPropagatesStopDuringInFlightStart() async {
        let driver = BlockingSessionDriver()
        let runner = driver.makeRunner()

        let startTask = Task {
            try await runner.startRunningIfNeeded()
        }

        await driver.waitForStartEntered()
        runner.stopRunningIfNeeded()
        driver.allowStartToFinish()

        do {
            try await startTask.value
            XCTFail("Expected startRunningIfNeeded to throw CancellationError")
        } catch is CancellationError {
            // Expected cancellation when stopped during startup.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(driver.startCallCount, 1)
        XCTAssertEqual(driver.stopCallCount, 1)
        XCTAssertFalse(driver.isRunning)
    }

    func test_stoppedInFlightStartDoesNotRegisterObserversOrBlockAnotherStreamSource() async throws {
        let firstDriver = BlockingSessionDriver()
        let firstOrientationProvider = SpyVideoOrientationProvider()
        let firstSource = DualCameraCameraStreamSource(
            orientationProvider: firstOrientationProvider,
            sessionRunner: firstDriver.makeRunner()
        )
        let sleeper = ManualSessionStopSleeper()
        let firstController = DualCameraController(
            streamSource: firstSource,
            sessionStopDelay: .milliseconds(20),
            sessionStopSleeper: { duration in
                await sleeper.sleep(for: duration)
            }
        )

        let startTask = Task {
            try await firstController.startSession()
        }

        await firstDriver.waitForStartEntered()
        firstController.stopSession()
        await sleeper.waitForSleepRequests(1)
        sleeper.finishNextSleep()
        await Task.yield()
        firstDriver.allowStartToFinish()

        do {
            try await startTask.value
            XCTFail("Expected in-flight startSession to throw CancellationError after delayed stop")
        } catch is CancellationError {
            // Expected cancellation when delayed stop runs during hardware startup.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(firstOrientationProvider.startObservingCallCount, 0)
        XCTAssertFalse(firstDriver.isRunning)

        let secondDriver = BlockingSessionDriver(blocksOnStart: false)
        let secondOrientationProvider = SpyVideoOrientationProvider()
        let secondSource = DualCameraCameraStreamSource(
            orientationProvider: secondOrientationProvider,
            sessionRunner: secondDriver.makeRunner()
        )
        defer { secondSource.stopSession() }

        try await secondSource.startSession()
        XCTAssertEqual(secondOrientationProvider.startObservingCallCount, 1)
        XCTAssertTrue(secondDriver.isRunning)
    }

    private func makePixelBuffer(color: UIColor) throws -> CVPixelBuffer {
        guard let buffer = color.asImage(CGSize(width: 4, height: 4)).pixelBuffer() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return buffer
    }
}

@MainActor
private final class RecordingPhotoCapturer: DualCameraPhotoCapturing {
    var rawFrontBuffer: CVPixelBuffer?
    var rawBackBuffer: CVPixelBuffer?
    var composedContentMode: DualCameraContentMode?
    var composedOverlayInsets: EdgeInsets?

    func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage) {
        rawFrontBuffer = frontBuffer
        rawBackBuffer = backBuffer
        return (UIImage(), UIImage())
    }

    // swiftlint:disable:next function_parameter_count
    func captureComposedPhoto(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        composedContentMode = contentMode
        composedOverlayInsets = overlayInsets
        return UIImage()
    }
}

@MainActor
private final class ManualSessionStopSleeper {
    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var readySleepCount = 0

    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async {
        requestedDurations.append(duration)

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
            readySleepCount += 1
            resumeReadyWaiters()
        }
    }

    func waitForSleepRequests(_ count: Int) async {
        guard readySleepCount < count else { return }

        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func finishNextSleep() {
        guard !sleepContinuations.isEmpty else { return }
        sleepContinuations.removeFirst().resume()
    }

    private func resumeReadyWaiters() {
        let readyWaiters = waiters.filter { readySleepCount >= $0.count }
        waiters.removeAll { readySleepCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}

@MainActor
private final class SpyCameraStreamSource: DualCameraCameraStreamSourcing {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    var torchModes: [AVCaptureDevice.TorchMode] = []
    nonisolated(unsafe) var framePair: DualCameraFramePair?
    nonisolated(unsafe) var frames: [DualCameraSource: PixelBufferWrapper] = [:]
    nonisolated(unsafe) var recordedEvents: [DualCameraDiagnosticEvent] = []
    private var stopWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func startSession() async throws {
        startCount += 1

        if let startError {
            throw startError
        }
    }

    func stopSession() {
        stopCount += 1
        resumeReadyStopWaiters()
    }

    func waitForStopCount(_ count: Int) async {
        guard stopCount < count else { return }

        await withCheckedContinuation { continuation in
            stopWaiters.append((count, continuation))
        }
    }

    nonisolated func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper? {
        frames[source]
    }

    nonisolated func subscribeToFramePairs() -> AsyncStream<DualCameraFramePair> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func latestFramePair() -> DualCameraFramePair? {
        framePair
    }

    nonisolated func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent) {
        recordedEvents.append(event)
    }

    nonisolated func diagnosticsSnapshot() -> DualCameraDiagnostics {
        DualCameraDiagnostics()
    }

    func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities {
        .unavailable(for: source)
    }

    @discardableResult
    func applyTorchMode(
        _ mode: AVCaptureDevice.TorchMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        torchModes.append(mode)
        return .applied
    }

    @discardableResult
    func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyFocusMode(
        _ mode: AVCaptureDevice.FocusMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyExposureMode(
        _ mode: AVCaptureDevice.ExposureMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    private func resumeReadyStopWaiters() {
        let readyWaiters = stopWaiters.filter { stopCount >= $0.count }
        stopWaiters.removeAll { stopCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}

@MainActor
private final class SpyVideoOrientationProvider: DualCameraVideoOrientationProviding {
    var currentVideoRotationAngle: CGFloat = 90
    private(set) var startObservingCallCount = 0
    private(set) var stopObservingCallCount = 0

    func startObserving(_ onChange: @escaping @MainActor @Sendable (CGFloat) -> Void) {
        startObservingCallCount += 1
        onChange(currentVideoRotationAngle)
    }

    func stopObserving() {
        stopObservingCallCount += 1
    }
}

private final class BlockingSessionDriver: @unchecked Sendable {
    private let lock = NSLock()
    private let startEnteredSemaphore = DispatchSemaphore(value: 0)
    private let allowStartToFinishSemaphore = DispatchSemaphore(value: 0)
    private let blocksOnStart: Bool
    private var running = false
    private var startCallCountStorage = 0
    private var stopCallCountStorage = 0

    init(blocksOnStart: Bool = true) {
        self.blocksOnStart = blocksOnStart
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var startCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCallCountStorage
    }

    var stopCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stopCallCountStorage
    }

    func makeRunner() -> SessionLifecycleRunner {
        SessionLifecycleRunner(
            isRunning: { [weak self] in
                self?.isRunning ?? false
            },
            startRunning: { [weak self] in
                self?.handleStartRunning()
            },
            stopRunning: { [weak self] in
                self?.handleStopRunning()
            }
        )
    }

    func waitForStartEntered() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [startEnteredSemaphore] in
                startEnteredSemaphore.wait()
                continuation.resume()
            }
        }
    }

    func allowStartToFinish() {
        allowStartToFinishSemaphore.signal()
    }

    private func handleStartRunning() {
        lock.lock()
        startCallCountStorage += 1
        lock.unlock()

        startEnteredSemaphore.signal()
        if blocksOnStart {
            allowStartToFinishSemaphore.wait()
        }

        lock.lock()
        running = true
        lock.unlock()
    }

    private func handleStopRunning() {
        lock.lock()
        stopCallCountStorage += 1
        running = false
        lock.unlock()
    }
}
