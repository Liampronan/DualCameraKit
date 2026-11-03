import AVFoundation
import DualCameraKit
import XCTest

@MainActor
final class DualCameraCameraStreamSourceTests: XCTestCase {
    func test_mockStreamSourcePublishesLatestFramesOnStart() async throws {
        let source = DualCameraMockCameraStreamSource()

        try await source.startSession()

        XCTAssertNotNil(source.latestFrame(for: .front))
        XCTAssertNotNil(source.latestFrame(for: .back))
        XCTAssertNotNil(source.latestFramePair())
    }

    func test_mockStreamSourceReplaysLatestFrameToNewSubscriber() async throws {
        let source = DualCameraMockCameraStreamSource()
        try await source.startSession()

        var iterator = source.subscribe(to: .front).makeAsyncIterator()
        let frame = await iterator.next()

        XCTAssertNotNil(frame)
    }

    func test_mockStreamSourceTracksTorchMode() async throws {
        let source = DualCameraMockCameraStreamSource()

        try source.applyTorchMode(.on, for: .back)

        XCTAssertEqual(source.torchMode, .on)
    }

    func test_mockStreamSourceReportsPerCameraCapabilities() throws {
        let source = DualCameraMockCameraStreamSource()

        let frontCapabilities = try source.cameraCapabilities(for: .front)
        let backCapabilities = try source.cameraCapabilities(for: .back)

        XCTAssertFalse(frontCapabilities.supportsTorch)
        XCTAssertTrue(backCapabilities.supportsTorch)
        XCTAssertEqual(backCapabilities.zoom.minimumFactor, 1)
        XCTAssertEqual(backCapabilities.zoom.maximumFactor, 8)
        XCTAssertTrue(backCapabilities.supportedFocusModes.contains(.continuousAutoFocus))
    }

    func test_mockStreamSourceEmitsDiagnosticsForAdjustedControls() async throws {
        let source = DualCameraMockCameraStreamSource()
        var iterator = source.diagnosticEvents().makeAsyncIterator()

        let result = try source.applyZoomFactor(12, for: .front)
        let event = await iterator.next()

        XCTAssertEqual(
            result,
            .adjusted(requestedValueDescription: "12.0", appliedValueDescription: "8.0")
        )
        XCTAssertEqual(event?.kind, .controlAdjusted)
        XCTAssertEqual(source.diagnosticsSnapshot().controlAdjustmentCount, 1)
        XCTAssertEqual(source.diagnosticsSnapshot().latestEvent?.kind, .controlAdjusted)
    }
}
