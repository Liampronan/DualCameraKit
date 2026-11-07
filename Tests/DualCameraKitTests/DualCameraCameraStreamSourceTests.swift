import AVFoundation
@testable import DualCameraKit
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

    func test_handleSystemPressureChange_emitsElevatedEventsAndDeduplicatesPerSource() async {
        let runner = SessionLifecycleRunner(isRunning: { false }, startRunning: {}, stopRunning: {})
        let source = DualCameraCameraStreamSource(sessionRunner: runner)
        var iterator = source.diagnosticEvents().makeAsyncIterator()

        source.handleSystemPressureChange(level: .nominal, for: .front)
        source.handleSystemPressureChange(level: .fair, for: .back)
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 0)
        XCTAssertNil(source.diagnosticsSnapshot().latestEvent)

        source.handleSystemPressureChange(level: .serious, for: .front)
        let firstEvent = await iterator.next()
        XCTAssertEqual(firstEvent?.kind, .systemPressureElevated)
        XCTAssertEqual(
            firstEvent?.context,
            .systemPressure(
                source: .front,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.serious.rawValue
            )
        )
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 1)

        // Repeated identical level for the same camera source is deduplicated
        source.handleSystemPressureChange(level: .serious, for: .front)
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 1)

        // Different camera source at the same level still emits an event
        source.handleSystemPressureChange(level: .serious, for: .back)
        let secondEvent = await iterator.next()
        XCTAssertEqual(
            secondEvent?.context,
            .systemPressure(
                source: .back,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.serious.rawValue
            )
        )
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 2)
    }

    func test_handleSystemPressureChange_escalatesAndResetsAfterNominalOrFair() async {
        let runner = SessionLifecycleRunner(isRunning: { false }, startRunning: {}, stopRunning: {})
        let source = DualCameraCameraStreamSource(sessionRunner: runner)
        var iterator = source.diagnosticEvents().makeAsyncIterator()

        source.handleSystemPressureChange(level: .serious, for: .front)
        _ = await iterator.next()

        source.handleSystemPressureChange(level: .critical, for: .front)
        let criticalEvent = await iterator.next()
        XCTAssertEqual(
            criticalEvent?.context,
            .systemPressure(
                source: .front,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.critical.rawValue
            )
        )

        source.handleSystemPressureChange(level: .shutdown, for: .front)
        let shutdownEvent = await iterator.next()
        XCTAssertEqual(
            shutdownEvent?.context,
            .systemPressure(
                source: .front,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.shutdown.rawValue
            )
        )
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 3)

        // Returning to fair/nominal resets deduplication state for that source
        source.handleSystemPressureChange(level: .fair, for: .front)
        source.handleSystemPressureChange(level: .serious, for: .front)
        let afterFairEvent = await iterator.next()
        XCTAssertEqual(
            afterFairEvent?.context,
            .systemPressure(
                source: .front,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.serious.rawValue
            )
        )
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 4)

        source.handleSystemPressureChange(level: .nominal, for: .front)
        source.handleSystemPressureChange(level: .critical, for: .front)
        let afterNominalEvent = await iterator.next()
        XCTAssertEqual(
            afterNominalEvent?.context,
            .systemPressure(
                source: .front,
                levelDescription: AVCaptureDevice.SystemPressureState.Level.critical.rawValue
            )
        )
        XCTAssertEqual(source.diagnosticsSnapshot().systemPressureWarningCount, 5)
    }
}
