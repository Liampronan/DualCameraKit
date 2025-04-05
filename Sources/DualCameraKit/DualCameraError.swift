import AVFoundation

public enum DualCameraError: Error, Equatable {
    case cameraUnavailable(position: AVCaptureDevice.Position)
    case captureFailure(CaptureFailureReason)
    case configurationFailed
    case multiCamNotSupported
    case multipleInstancesNotSupported
    case noRecordingInProgress
    case notImplemented
    case permissionDenied
    case recordingFailed(RecordingFailureReason)
    case recordingInProgress
    case sessionInterrupted(reason: AVCaptureSession.InterruptionReason)
    case unknownError
    
    // The existing nested enum pattern is good and should be followed
    public enum RecordingFailureReason: Sendable {
        case assetWriterConfigurationFailed
        case assetWriterCreationFailed
        case diskSpaceLow
        case fileOutputCreationFailed
        case noPermission
        case noPhotoCapturerAvailable
        case pixelBufferPoolCreationFailed
        case noVideoRecorderSet
        case unknown
    }
    
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
        case .noRecordingInProgress:
            return "Unable to stop recording because no recording is in progress."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .permissionDenied:
            return "Camera permission was denied – if you want to record please try again and accept the ReplayKit permission prompt."
        case .recordingFailed(let reason):
            switch reason {
            case .assetWriterConfigurationFailed:
                return "Failed to configure video recording settings."
            case .assetWriterCreationFailed:
                return "Failed to create video writer. The file may be in use or the destination might be invalid."
            case .diskSpaceLow:
                return "Insufficient disk space available for video recording."
            case .fileOutputCreationFailed:
                return "Failed to create file output for video recording."
            case .noPermission:
                return "Missing required permissions for video recording."
            case .noPhotoCapturerAvailable:
                return "No photo capturer avilable for video recording."
            case .pixelBufferPoolCreationFailed:
                return "Failed to create pixel buffer pool for video recording."
            case .noVideoRecorderSet:
                return "No Video Recorder set. Ensure that the controller has a valid video recorder set."
            case .unknown:
                return "An unknown error occurred during video recording."
            }
        case .recordingInProgress:
            return "Unable to start recording beecause recording is already in progress."
        case .sessionInterrupted(let reason):
            return "Capture session was interrupted: \(reason)."
        case .unknownError:
            return "An unknown error occurred in CameraManager."
        }
    }
}
