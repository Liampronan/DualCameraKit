import Foundation

/// How video recording should be performed
public enum DualCameraVideoRecordingMode: Sendable {
    /// Records what is displayed on screen (the composed view)
    case screenCapture(DualCameraPhotoCaptureMode = .fullScreen)
    
    /// Records directly from camera feeds
    case rawCapture(combineStreams: Bool = true)
    
    var asPhotoCaptureMode: DualCameraPhotoCaptureMode? {
        switch self {
        case .screenCapture(let mode): mode
        case .rawCapture: nil
        }
    }
}
