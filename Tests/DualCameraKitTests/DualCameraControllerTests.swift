import AVFoundation
import DualCameraKit
import XCTest

@MainActor
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
        contentMode: DualCameraContentMode
    ) async throws -> UIImage {
        composedContentMode = contentMode
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
        nil
    }

    nonisolated func subscribeToFramePairs() -> AsyncStream<DualCameraFramePair> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func latestFramePair() -> DualCameraFramePair? {
        framePair
    }

    nonisolated func diagnostics() -> DualCameraDiagnostics {
        DualCameraDiagnostics()
    }

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        torchModes.append(mode)
    }

    func setZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws {}

    func setFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws {}

    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws {}

    func setWhiteBalanceMode(_ mode: AVCaptureDevice.WhiteBalanceMode, for source: DualCameraSource) throws {}

    private func resumeReadyStopWaiters() {
        let readyWaiters = stopWaiters.filter { stopCount >= $0.count }
        stopWaiters.removeAll { stopCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}
