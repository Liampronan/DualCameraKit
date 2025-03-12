import AVFoundation

public enum DualCameraError: Error {
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case permissionDenied
    case configurationFailed
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError
    case notImplemented
    case captureFailure(CaptureFailureReason)
    
    // Adding proper dedicated error cases for recording
    case recordingInProgress
    case noRecordingInProgress
    case recordingFailed(RecordingFailureReason)
    
    // The existing nested enum pattern is good and should be followed
    public enum RecordingFailureReason: Sendable {
        case assetWriterCreationFailed
        case assetWriterConfigurationFailed
        case pixelBufferPoolCreationFailed
        case fileOutputCreationFailed
        case noPermission
        case diskSpaceLow
        case unknown
    }
    
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
            case .recordingInProgress:
                return "Unable to start recording beecause recording is already in progress."
            case .noRecordingInProgress:
                return "Unable to stop recording because no recording is in progress."
            case .notImplemented:
                return "This feature is not yet implemented."
            case .recordingFailed(let reason):
                switch reason {
                case .assetWriterCreationFailed:
                    return "Failed to create video writer. The file may be in use or the destination might be invalid."
                case .assetWriterConfigurationFailed:
                    return "Failed to configure video recording settings."
                case .pixelBufferPoolCreationFailed:
                    return "Failed to create pixel buffer pool for video recording."
                case .fileOutputCreationFailed:
                    return "Failed to create file output for video recording."
                case .noPermission:
                    return "Missing required permissions for video recording."
                case .diskSpaceLow:
                    return "Insufficient disk space available for video recording."
                case .unknown:
                    return "An unknown error occurred during video recording."
                }
            }
        }
}
