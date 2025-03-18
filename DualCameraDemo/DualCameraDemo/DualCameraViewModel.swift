import DualCameraKit
import Observation
import Photos
import SwiftUI

@MainActor
@Observable
final class DualCameraViewModel {
    // Core state
    private(set) var viewState: CameraViewState = .loading
    
    // Configuration
    var configuration = CameraConfiguration()
    
    // User artifacts
    private(set) var capturedImage: UIImage? = nil
    var alert: AlertState? = nil
    
    let dualCameraController: DualCameraControlling
    private var recordingTimer: Timer?
    
    init(dualCameraController: DualCameraControlling) {
        self.dualCameraController = dualCameraController
    }
     
    // MARK: - Lifecycle Management
    
    func onAppear(containerSize: CGSize) {
        configuration.containerSize = containerSize
        
        // Start camera session
        Task {
            do {
                viewState = .loading
                try await dualCameraController.startSession()
                viewState = .ready
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Failed to start camera")
            } catch {
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Failed to start camera")
            }
        }
    }
    
    func onDisappear() {
        // Clean up resources
        if case .recording = viewState {
            stopRecording()
        }
        
        dualCameraController.stopSession()
        
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Configuration Updates
    
    func containerSizeChanged(_ newSize: CGSize) {
        configuration.containerSize = newSize
    }
    
    func updateLayout(_ newLayout: CameraLayout) {
        configuration.layout = newLayout
    }
    
    // MARK: - User Actions
    
    func dismissCapturedImage() {
        capturedImage = nil
    }
    
    func takePhoto() {
        Task {
            guard case .ready = viewState else { return }
            
            viewState = .capturing
            
            do {
                // Capture screen
                let image = try await dualCameraController.captureCurrentScreen()
                capturedImage = image
                viewState = .ready
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Error capturing photo")
                // Reset to ready state after error
                viewState = .ready
            } catch {
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Error capturing photo")
                // Reset to ready state after error
                viewState = .ready
            }
        }
    }
    
    func toggleRecording() {
        if case .recording = viewState {
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
                alert = .permissionDenied(message: "Photo library access is required to save videos.")
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    // Create a temporary file URL in the documents directory
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
                    let fileURL = tempDir.appendingPathComponent(fileName)
                    
                    // Save for later use when stopping recording
                    
                    // Start recording
                    try await dualCameraController.startVideoRecording(outputURL: fileURL)
                    
                    // Update state to recording with 0 duration
                    viewState = .recording(CameraViewState.RecordingState(duration: 0))
                    
                    // Start a timer to update recording duration
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if case .recording(let state) = self.viewState {
                                self.viewState = .recording(CameraViewState.RecordingState(duration: state.duration + 1))
                            }
                        }
                    }
                    
                } catch let error as DualCameraError {
                    viewState = .error(error)
                    showError(error, message: "Failed to start recording")
                    // Reset to ready state after error
                    viewState = .ready
                } catch {
                    let dualCameraError = DualCameraError.unknownError
                    viewState = .error(dualCameraError)
                    showError(error, message: "Failed to start recording")
                    // Reset to ready state after error
                    viewState = .ready
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
                let videoRecordingOutputURL = try await dualCameraController.stopVideoRecording()
                
                // Reset recording state
                viewState = .ready
                
                // Save video to photo library
                saveVideoToPhotoLibrary(videoRecordingOutputURL)
                
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Failed to stop recording")
                // Reset to ready state even if there was an error
                viewState = .ready
            } catch {
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Failed to stop recording")
                // Reset to ready state even if there was an error
                viewState = .ready
            }
        }
    }
    
    // MARK: - Permissions
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                Task { @MainActor in
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
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
                    self.alert = .info(title: "Video Recording", message: "Video saved to photo library")
                    
                    // Clean up the temp file
                    try? FileManager.default.removeItem(at: videoURL)
                } else if let error = error {
                    self.showError(error, message: "Failed to save video")
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func showError(_ error: Error, message: String) {
        let errorMessage = "\(message): \(error.localizedDescription)"
        print(errorMessage)
        
        alert = .info(title: "Error", message: errorMessage)
    }
}

// MARK: - UI State Helpers

extension CameraViewState {
    // Button state helpers
    var isPhotoButtonEnabled: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isVideoButtonEnabled: Bool {
        if case .capturing = self { return false }
        return true
    }
    
    // UI representation helpers
    var videoButtonIcon: String {
        if case .recording = self { return "stop.fill" }
        return "record.circle"
    }
    
    var videoButtonColor: Color {
        if case .recording = self { return .red }
        return .white
    }
    
    var videoButtonBackgroundColor: Color {
        if case .recording = self { return Color.white.opacity(0.8) }
        return Color.black.opacity(0.5)
    }
}
