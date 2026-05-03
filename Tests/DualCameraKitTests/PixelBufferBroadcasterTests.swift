@testable import DualCameraKit
import UIKit
import XCTest

final class PixelBufferBroadcasterTests: XCTestCase {
    func test_sendFansOutToAllSubscribers() async throws {
        let broadcaster = PixelBufferBroadcaster()
        var first = broadcaster.subscribe().makeAsyncIterator()
        var second = broadcaster.subscribe().makeAsyncIterator()
        let wrapper = try makePixelBufferWrapper(color: .red)

        broadcaster.send(wrapper)

        let firstValue = await first.next()
        let secondValue = await second.next()
        XCTAssertTrue(firstValue?.buffer === wrapper.buffer)
        XCTAssertTrue(secondValue?.buffer === wrapper.buffer)
    }

    func test_subscriberCancellationRemovesContinuation() async throws {
        let broadcaster = PixelBufferBroadcaster()
        let stream = broadcaster.subscribe()

        let task = Task {
            for await _ in stream {}
        }
        await Task.yield()
        XCTAssertEqual(broadcaster.subscriberCount, 1)

        task.cancel()
        await Task.yield()
        XCTAssertEqual(broadcaster.subscriberCount, 0)
    }

    func test_slowSubscriberReceivesNewestBufferedFrame() async throws {
        let broadcaster = PixelBufferBroadcaster()
        var iterator = broadcaster.subscribe().makeAsyncIterator()
        let first = try makePixelBufferWrapper(color: .red)
        let second = try makePixelBufferWrapper(color: .green)
        let third = try makePixelBufferWrapper(color: .blue)

        broadcaster.send(first)
        broadcaster.send(second)
        broadcaster.send(third)

        let value = await iterator.next()
        XCTAssertTrue(value?.buffer === third.buffer)
    }

    private func makePixelBufferWrapper(color: UIColor) throws -> PixelBufferWrapper {
        guard let buffer = color.asImage(CGSize(width: 4, height: 4)).pixelBuffer() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return PixelBufferWrapper(buffer: buffer)
    }
}
