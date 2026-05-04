import AVFoundation

public enum DualCameraError: Error, Equatable {
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case captureFailure(CaptureFailureReason)
    case configurationFailed
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case notImplemented
    case permissionDenied
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError

    public enum CaptureFailureReason: Sendable {
        case commandBufferCreationFailed
        case contextCreationFailed
        case imageCreationFailed
        case memoryAllocationFailed
        case noFrameAvailable
        case noPrimaryRenderer
        case screenCaptureUnavailable
        case textureCreationFailed
        case unknownDimensions
    }

    public var localizedDescription: String {
        switch self {
        case .cameraUnavailable(let position):
            return "Camera at position \(position) is unavailable."
        case .captureFailure(let reason):
            switch reason {
            case .commandBufferCreationFailed:
                return "Failed to create Metal command buffer."
            case .contextCreationFailed:
                return "Failed to create graphics context."
            case .imageCreationFailed:
                return "Failed to create image from texture data."
            case .memoryAllocationFailed:
                return "Failed to allocate memory for image data."
            case .noFrameAvailable:
                return "No frame available to capture."
            case .noPrimaryRenderer:
                return "No primary renderer available for capture."
            case .screenCaptureUnavailable:
                return "Screen capture not available."
            case .textureCreationFailed:
                return "Failed to create texture for capture."
            case .unknownDimensions:
                return "Unknown screen dimensions for capture."
            }
        case .configurationFailed:
            return "Failed to configure the AVCaptureSession."
        case .multiCamNotSupported:
            return "Multi-camera capture is not supported on this device."
        case .multipleInstancesNotSupported:
            return "Multiple instances of DualCameraManager not supported."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .permissionDenied:
            return "Camera permission was denied by the user."
        case .sessionInterrupted(let reason):
            return "Capture session was interrupted: \(reason)."
        case .unknownError:
            return "An unknown error occurred in CameraManager."
        }
    }
}
