import DualCameraKit
import Foundation

/// Describes the current mode of the camera system
enum CameraViewState: Equatable {
    case loading
    case ready
    case capturing
    case error(DualCameraError)
    
    var captureInProgress: Bool {
        self == .capturing
    }
}
