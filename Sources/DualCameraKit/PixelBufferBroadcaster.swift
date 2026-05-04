import AVFoundation

/// Multi-consumer pixel buffer broadcaster.
/// Each subscriber keeps only the newest frame so slow consumers do not build
/// unbounded camera-frame queues.
final class PixelBufferBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<PixelBufferWrapper>.Continuation] = [:]
    private var latestBuffer: PixelBufferWrapper?

    init() {}

    /// Sends a new pixel buffer to all subscribers.
    func send(_ buffer: PixelBufferWrapper) {
        lock.lock()
        latestBuffer = buffer
        let activeContinuations = continuations
        lock.unlock()

        for continuation in activeContinuations.values {
            continuation.yield(buffer)
        }
    }

    /// Returns the newest buffer seen by the broadcaster.
    var latestValue: PixelBufferWrapper? {
        lock.lock()
        defer { lock.unlock() }
        return latestBuffer
    }

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    /// Creates a new subscription to the pixel buffer stream
    func subscribe() -> AsyncStream<PixelBufferWrapper> {
        let id = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[id] = continuation
            let bufferedValue = latestBuffer
            lock.unlock()

            if let bufferedValue {
                continuation.yield(bufferedValue)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }
}
