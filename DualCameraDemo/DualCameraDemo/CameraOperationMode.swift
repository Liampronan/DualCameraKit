import Foundation

/// Represents the current camera operation mode
public enum CameraOperationMode: Equatable {
    /// Camera is on but not recording/capturing
    case idle
    /// Taking a photo
    case capturing
    /// Recording video with current duration
    case recording(duration: TimeInterval)
    
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
    
    var isCapturing: Bool {
        if case .capturing = self { return true }
        return false
    }
    
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
    
    var recordingDuration: TimeInterval {
        if case .recording(let duration) = self {
            return duration
        }
        return 0
    }
}
