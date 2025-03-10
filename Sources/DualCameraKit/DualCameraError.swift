import AVFoundation

public enum DualCameraError: Error {
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case permissionDenied
    case configurationFailed
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError
    case captureFailure(CaptureFailureReason)
    
    public enum CaptureFailureReason: Sendable {
        case noPrimaryRenderer
        case noFrameAvailable
        case textureCreationFailed
        case commandBufferCreationFailed
        case memoryAllocationFailed
        case contextCreationFailed
        case imageCreationFailed
        case screenCaptureUnavailable
        case unknownDimensions
    }

    public var localizedDescription: String {
            switch self {
            case .multiCamNotSupported:
                return "Multi-camera capture is not supported on this device."
            case .multipleInstancesNotSupported:
                return "Multiple instances of DualCameraManager not supported."
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
            case .captureFailure(let reason):
                switch reason {
                case .noPrimaryRenderer:
                    return "No primary renderer available for capture."
                case .noFrameAvailable:
                    return "No frame available to capture."
                case .textureCreationFailed:
                    return "Failed to create texture for capture."
                case .commandBufferCreationFailed:
                    return "Failed to create Metal command buffer."
                case .memoryAllocationFailed:
                    return "Failed to allocate memory for image data."
                case .contextCreationFailed:
                    return "Failed to create graphics context."
                case .imageCreationFailed:
                    return "Failed to create image from texture data."
                case .screenCaptureUnavailable:
                    return "Screen capture not available."
                case .unknownDimensions:
                    return "Unknown screen dimensions for capture."
                }
            }
        }
}
