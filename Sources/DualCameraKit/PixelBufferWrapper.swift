import AVFoundation

/// A thin wrapper around `CVPixelBuffer` marked `@unchecked Sendable`.
///
/// Swift's concurrency model doesn't consider `CVPixelBuffer` to be automatically
/// sendable because it references potentially mutable memory. By wrapping it
/// in `PixelBufferWrapper`, we locally assert that passing the buffer across
/// concurrency boundaries is safe *for our read-only use cases*.
///
/// - Important: This does **not** guarantee immutability of the underlying
///   pixel buffer. Hardware or system components may still mutate it behind
///   the scenes. If you need a truly immutable copy, you must create your own
///   copy of the pixel data. Use this wrapper only when you're certain your
///   usage of `CVPixelBuffer` is read-only or otherwise thread-safe.
public struct PixelBufferWrapper: @unchecked Sendable {
    let buffer: CVPixelBuffer
}
