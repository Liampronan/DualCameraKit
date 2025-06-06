import Foundation

/// Describes the current mode of the camera system
enum CameraViewState: Equatable {
    case loading
    case ready
    case precapture
    case capturing
    case recording(RecordingState)
    case error(DualCameraError)
    
    struct RecordingState: Equatable {
        let duration: TimeInterval
        
        var formattedDuration: String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var captureInProgress: Bool {
        if case .recording(_) = self { return true }
        return self == .precapture || self == .capturing
    }
}
