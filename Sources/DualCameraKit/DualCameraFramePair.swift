import AVFoundation

/// A synchronized front/back camera frame pair.
public struct DualCameraFramePair: Sendable {
    public let front: PixelBufferWrapper
    public let back: PixelBufferWrapper
    public let timestamp: CMTime?

    public init(front: PixelBufferWrapper, back: PixelBufferWrapper, timestamp: CMTime? = nil) {
        self.front = front
        self.back = back
        self.timestamp = timestamp
    }
}
