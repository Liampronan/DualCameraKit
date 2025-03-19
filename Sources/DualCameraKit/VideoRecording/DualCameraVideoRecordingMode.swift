import Foundation

/// How video recording should be performed
public enum DualCameraVideoRecordingMode: Sendable {
    /// Records what is displayed on screen (the composed view)
    case screenCapture(DualCameraCaptureMode = .fullScreen)
    
    /// Records directly from camera feeds
    case rawCapture(combineStreams: Bool = true)
}
