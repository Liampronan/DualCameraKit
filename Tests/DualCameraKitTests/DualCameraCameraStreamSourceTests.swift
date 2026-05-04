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

        try source.setTorchMode(.on)

        XCTAssertEqual(source.torchMode, .on)
    }
}
