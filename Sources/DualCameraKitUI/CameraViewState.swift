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

    /// Indicates whether the shutter button should be enabled for the current view state.
    var isPhotoButtonEnabled: Bool {
        if case .ready = self { return true }
        return false
    }
}
