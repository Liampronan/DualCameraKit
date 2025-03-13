import DualCameraKit
import SwiftUI
import Photos
import Observation

// MARK: - State Types
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

/// Represents permission states
public enum PermissionStatus: Equatable {
    case unknown
    case checking
    case authorized
    case denied
    case restricted
    case limited
}

// MARK: - State
/// Encapsulates all application state in one place
public struct DualCameraState: Equatable {
    // Camera and layout state
    var cameraLayout: CameraLayout = .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    var containerSize: CGSize = .zero
    
    // Operational state
    var operationMode: CameraOperationMode = .idle
    var capturedImage: UIImage? = nil
    
    // Permission state
    var permissionStatus: PermissionStatus = .unknown
    
    // Alert state
    var alert: AlertState? = nil
    
    // Permission status with descriptive states
    enum PermissionStatus {
        case unknown
        case checking
        case authorized
        case denied
        case restricted
        case limited
    }
}

// MARK: - ViewModel
@MainActor
@Observable
public final class DualCameraViewModel {
    // The camera controller - hardware interface
    let dualCameraController = DualCameraController()
    
    // The application state
    var state = DualCameraState()
    
    // Internal timer for recording duration updates
    private var recordingTimer: Timer?
    
    public init() {}
    
    // MARK: - Lifecycle
    
    func onAppear(containerSize: CGSize) {
        state.containerSize = containerSize
        
        // Start camera session
        Task {
            do {
                try await dualCameraController.startSession()
            } catch {
                handleError(error, message: "Failed to start camera")
            }
        }
    }
    
    func onDisappear() {
        // Clean up resources
        if state.operationMode.isRecording {
            stopRecording()
        }
        
        dualCameraController.stopSession()
        
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Container Size Updates
    
    func containerSizeChanged(_ newSize: CGSize) {
        state.containerSize = newSize
    }
    
    // MARK: - Actions
    
    func dismissCapturedImage() {
        state.capturedImage = nil
    }
    
    func takePhoto() {
        Task {
            guard case .idle = state.operationMode else { return }
            
            state.operationMode = .capturing
            
            do {
                // Capture screen
                let image = try await dualCameraController.captureCurrentScreen()
                state.capturedImage = image
            } catch {
                handleError(error, message: "Error capturing photo")
            }
            
            state.operationMode = .idle
        }
    }
    
    func toggleRecording() {
        if state.operationMode.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // MARK: - Recording Implementation
    
    private func startRecording() {
        checkPhotoLibraryPermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            guard hasPermission else {
                self.state.alert = .permissionDenied(message: "Photo library access is required to save videos.")
                return
            }
            
            Task { [weak self] in
                guard let self else { return }
                do {
                    // Create a temporary file URL in the documents directory
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
                    let fileURL = tempDir.appendingPathComponent(fileName)
                    
                    // Start recording - assuming this method exists in DualCameraController
                    try await dualCameraController.startVideoRecording(
                        mode: .screenCapture(.fullScreen),
                        outputURL: fileURL
                    )
                    
                    // Update state
                    state.operationMode = .recording(duration: 0)
                    
                    // Start a timer to update recording duration
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if case .recording(let currentDuration) = state.operationMode {
                                state.operationMode = .recording(duration: currentDuration + 1)
                            }
                        }
                    }
                    
                } catch {
                    handleError(error, message: "Failed to start recording")
                }
            }
        }
    }
    
    private func stopRecording() {
        // Stop the timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop recording
        Task {
            do {
                // Stop recording and get output URL - assuming this method exists
                let outputURL = try await dualCameraController.stopVideoRecording()
                
                // Reset recording state
                state.operationMode = .idle
                
                // Save video to photo library
                saveVideoToPhotoLibrary(outputURL)
                
            } catch {
                handleError(error, message: "Failed to stop recording")
                
                // Reset recording state even if there was an error
                state.operationMode = .idle
            }
        }
    }
    
    // MARK: - Permissions
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        state.permissionStatus = .checking
        
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized:
            state.permissionStatus = .authorized
            completion(true)
        case .limited:
            state.permissionStatus = .limited
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    switch newStatus {
                    case .authorized:
                        state.permissionStatus = .authorized
                        completion(true)
                    case .limited:
                        state.permissionStatus = .limited
                        completion(true)
                    case .denied:
                        state.permissionStatus = .denied
                        completion(false)
                    case .restricted:
                        state.permissionStatus = .restricted
                        completion(false)
                    default:
                        state.permissionStatus = .unknown
                        completion(false)
                    }
                }
            }
        case .denied:
            state.permissionStatus = .denied
            completion(false)
        case .restricted:
            state.permissionStatus = .restricted
            completion(false)
        @unknown default:
            state.permissionStatus = .unknown
            completion(false)
        }
    }
    
    // MARK: - Photo Library
    
    private func saveVideoToPhotoLibrary(_ videoURL: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        } completionHandler: { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if success {
                    // Show success alert
                    state.alert = .info(title: "Video Recording", message: "Video saved to photo library")
                    
                    // Clean up the temp file
                    try? FileManager.default.removeItem(at: videoURL)
                } else if let error = error {
                    handleError(error, message: "Failed to save video")
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error, message: String) {
        let errorMessage = "\(message): \(error.localizedDescription)"
        print(errorMessage)
        
        state.alert = .info(title: "Error", message: errorMessage)
    }
    
    // MARK: - Helpers
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
