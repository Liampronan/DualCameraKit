import AVFoundation
import DualCameraKit
import XCTest

@MainActor
final class DualCameraControllerTests: XCTestCase {
    func test_stopSessionDebouncesDuringNavigationHandoff() async throws {
        let streamSource = SpyCameraStreamSource()
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(50)
        )

        try await controller.startSession()
        controller.stopSession()
        try await controller.startSession()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(streamSource.startCount, 1)
        XCTAssertEqual(streamSource.stopCount, 0)

        controller.stopSession()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(streamSource.stopCount, 1)
    }

    func test_stopSessionWaitsForAllActiveUsers() async throws {
        let streamSource = SpyCameraStreamSource()
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(20)
        )

        try await controller.startSession()
        try await controller.startSession()

        controller.stopSession()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(streamSource.stopCount, 0)

        controller.stopSession()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(streamSource.stopCount, 1)
    }

    func test_startSessionFailureReleasesUseCount() async throws {
        let streamSource = SpyCameraStreamSource()
        streamSource.startError = DualCameraError.unknownError
        let controller = DualCameraController(
            streamSource: streamSource,
            sessionStopDelay: .milliseconds(20)
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
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(streamSource.startCount, 2)
        XCTAssertEqual(streamSource.stopCount, 1)
    }
}

@MainActor
private final class SpyCameraStreamSource: DualCameraCameraStreamSourcing {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    var torchModes: [AVCaptureDevice.TorchMode] = []

    func startSession() async throws {
        startCount += 1

        if let startError {
            throw startError
        }
    }

    func stopSession() {
        stopCount += 1
    }

    nonisolated func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper? {
        nil
    }

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        torchModes.append(mode)
    }
}
