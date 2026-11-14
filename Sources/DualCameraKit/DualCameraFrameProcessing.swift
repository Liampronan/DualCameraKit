import CoreVideo

/// Metadata describing a camera frame passed into a `DualCameraFrameProcessing` plugin.
public struct DualCameraFrameContext: Sendable, Equatable {
    /// Indicates how the processed frame will be consumed.
    public enum Purpose: Sendable, Equatable {
        /// Frame is destined for real-time display in a `CameraRenderer`.
        case livePreview
        /// Frame will be composited into the combined dual-camera photo capture.
        case photoCaptureComposed
        /// Frame will be exported as a single-camera raw photo in `DualCameraCapturedPhotoSet` or `captureRawPhotos`.
        case photoCaptureRaw
    }

    /// Which camera produced the frame.
    public let source: DualCameraSource
    /// Whether the camera stream is horizontally mirrored.
    public let isMirrored: Bool
    /// How the processed frame will be used.
    public let purpose: Purpose

    /// Creates a frame processing context.
    public init(
        source: DualCameraSource,
        isMirrored: Bool,
        purpose: Purpose
    ) {
        self.source = source
        self.isMirrored = isMirrored
        self.purpose = purpose
    }
}

/// A pluggable processor that transforms camera pixel buffers before live preview rendering or photo capture.
public protocol DualCameraFrameProcessing: Sendable {
    /// Transforms `frame` for the given `context`, or returns `frame` unchanged when passing through.
    func process(
        frame: PixelBufferWrapper,
        context: DualCameraFrameContext
    ) async -> PixelBufferWrapper
}
