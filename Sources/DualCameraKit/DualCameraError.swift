import AVFoundation

public enum DualCameraError: LocalizedError, Equatable {
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case captureFailure(CaptureFailureReason)
    case configurationFailed
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case permissionDenied
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError

    public enum CaptureFailureReason: Sendable {
        case contextCreationFailed
        case imageCreationFailed
        case noFrameAvailable
        case unknownDimensions
    }

    public var localizedDescription: String {
        switch self {
        case .cameraUnavailable(let position):
            return "Camera at position \(position) is unavailable."
        case .captureFailure(let reason):
            switch reason {
            case .contextCreationFailed:
                return "Failed to create graphics context."
            case .imageCreationFailed:
                return "Failed to create image from texture data."
            case .noFrameAvailable:
                return "No frame available to capture."
            case .unknownDimensions:
                return "Unknown screen dimensions for capture."
            }
        case .configurationFailed:
            return "Failed to configure the AVCaptureSession."
        case .multiCamNotSupported:
            return "Multi-camera capture is not supported on this device."
        case .multipleInstancesNotSupported:
            return "Multiple instances of DualCameraManager not supported."
        case .permissionDenied:
            return "Camera permission was denied by the user."
        case .sessionInterrupted(let reason):
            return "Capture session was interrupted: \(reason)."
        case .unknownError:
            return "An unknown error occurred in CameraManager."
        }
    }

    /// Bridges `localizedDescription` to `NSError`, so alerts show the reason instead of "error 1".
    public var errorDescription: String? { localizedDescription }
}
