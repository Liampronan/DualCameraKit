import AsyncAlgorithms
import AVFoundation

/// Multi-consumer pixel buffer broadcaster using AsyncChannel.
/// We have multiple consumers for viewing and recording for example.
/// TODO: fixme @unchecked Sendable - consider making this an actor
public class PixelBufferBroadcaster: @unchecked Sendable {
    
    private let channel = AsyncChannel<PixelBufferWrapper>()
    
    /// Broadcasts a new pixel buffer to all subscribers
    public func broadcast(_ buffer: PixelBufferWrapper) async {
        await channel.send(buffer)
    }
    
    /// Creates a new subscription to the pixel buffer stream
    public func subscribe() -> AsyncStream<PixelBufferWrapper> {
        let localChannel = channel // Capture channel locally
        
        return AsyncStream { continuation in
            // Create a local task without capturing self
            let task = Task {
                do {
                    for await buffer in localChannel {
                        continuation.yield(buffer)
                    }
                } catch {
                    // TODO: Handle channel errors
                }
                continuation.finish()
            }
            
            // Clean up task on cancellation
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
