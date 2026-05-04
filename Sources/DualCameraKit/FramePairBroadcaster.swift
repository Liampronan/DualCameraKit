import Foundation

final class FramePairBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<DualCameraFramePair>.Continuation] = [:]
    private var latestFramePair: DualCameraFramePair?

    func send(_ framePair: DualCameraFramePair) {
        lock.lock()
        latestFramePair = framePair
        let activeContinuations = continuations
        lock.unlock()

        for continuation in activeContinuations.values {
            continuation.yield(framePair)
        }
    }

    var latestValue: DualCameraFramePair? {
        lock.lock()
        defer { lock.unlock() }
        return latestFramePair
    }

    func subscribe() -> AsyncStream<DualCameraFramePair> {
        let id = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[id] = continuation
            let bufferedValue = latestFramePair
            lock.unlock()

            if let bufferedValue {
                continuation.yield(bufferedValue)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }
}
