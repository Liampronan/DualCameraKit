import AVFoundation

/// Multi-consumer pixel buffer broadcaster using AsyncChannel.
/// We have multiple consumers for viewing and recording for example.
public class PixelBufferBroadcaster: @unchecked Sendable {
    // For thread safety
    private let lock = NSLock()
    
    // Storage for active continuations and buffered values
    private var continuations: [UUID: AsyncStream<PixelBufferWrapper>.Continuation] = [:]
    
    public init() {}
    
    /// Broadcasts a new pixel buffer to all subscribers
    public func broadcast(_ buffer: PixelBufferWrapper) async {
        lock.lock()
        let activeContinuations = continuations
        lock.unlock()
        
        // Send to all active subscribers
        for continuation in activeContinuations.values {
            continuation.yield(buffer)
        }
    }
    
    /// Creates a new subscription to the pixel buffer stream
    public func subscribe() -> AsyncStream<PixelBufferWrapper> {
        let id = UUID()
        
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            
            // Clean up on cancellation
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }
}
