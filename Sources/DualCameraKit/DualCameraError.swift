import AVFoundation

public enum DualCameraError: Error {
    public enum captureFailureError: Error {
        case noTextureAvailable
        case imageCreationFailed
        case noPrimaryRenderer
        
        public var localizedDescription: String {
            return switch self {
            case .noTextureAvailable: "No Metal texture available."
            case .imageCreationFailed: "Image creation failed."
            case .noPrimaryRenderer: "No primary renderer set."
            }
        }
    }
    case captureFailure(captureFailureError)
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case permissionDenied
    case configurationFailed
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError

    /// Provides human-readable descriptions for debugging
    public var localizedDescription: String {
        switch self {
        case .captureFailure(let captureFailureError):
            return captureFailureError.localizedDescription
        case .multiCamNotSupported:
            return "Multi-camera capture is not supported on this device."
        case .multipleInstancesNotSupported:
            return "Multiple instances of DualCameraManager not supported"
        case .cameraUnavailable(let position):
            return "Camera at position \(position) is unavailable."
        case .permissionDenied:
            return "Camera permission was denied by the user."
        case .configurationFailed:
            return "Failed to configure the AVCaptureSession."
        case .sessionInterrupted(let reason):
            return "Capture session was interrupted: \(reason)."
        case .unknownError:
            return "An unknown error occurred in CameraManager."
        }
    }
}
