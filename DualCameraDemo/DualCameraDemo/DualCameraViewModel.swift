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
    var videoRecorderType: DualCameraVideoRecorderType { configuration.videoRecorderType }
    
    // User artifacts
    private(set) var capturedImage: UIImage? = nil
    var alert: AlertState? = nil
    
    let controller: DualCameraControlling
    private var recordingTimer: Timer?
    
    init(dualCameraController: DualCameraControlling) {
        self.controller = dualCameraController
    }
    
    // MARK: - Lifecycle Management
    
    private func startSession() {
        Task {
            do {
                viewState = .loading
                try await controller.startSession()
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
    
    func onAppear(containerSize: CGSize) {
        configuration.containerSize = containerSize
        startSession()
    }
    
    func onDisappear() {
        // Clean up
        if case .recording = viewState {
            stopRecording()
        }
        controller.stopSession()
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
            
            let hasPermission = await checkPhotoLibraryPermission()
            
            guard hasPermission else {
                alert = .permissionDenied(message: "Photo library access is required to save photos.")
                return
            }
            
            viewState = .capturing
            
            do {
                let image = try await controller.captureCurrentScreen()
                viewState = .ready
                saveImageToPhotoLibrary(image)
                
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
    
    func toggleRecorderType() {
        if case .cpuBased = configuration.videoRecorderType {
            configuration.videoRecorderType = .replayKit()
        } else {
            configuration.videoRecorderType = .cpuBased(.init(mode: .fullScreen))
        }
    }
    
    // MARK: - Recording Implementation
    
    private func startRecording() {
        Task {
            let hasPermission = await checkPhotoLibraryPermission()
            
            guard hasPermission else {
                alert = .permissionDenied(message: "Photo library access is required to save videos.")
                return
            }
            
            do {
                try await controller.startVideoRecording(recorderType: configuration.videoRecorderType)
                
                viewState = .recording(CameraViewState.RecordingState(duration: 0))
                
                // Start a timer to update recording duration
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if case .recording(let state) = viewState {
                            viewState = .recording(CameraViewState.RecordingState(duration: state.duration + 1))
                        }
                    }
                }
                
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Failed to start recording")
                viewState = .ready
            } catch {
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Failed to start recording")
                viewState = .ready
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
                let videoRecordingOutputURL = try await controller.stopVideoRecording()
                
                // Reset recording state
                viewState = .ready
                
                saveVideoToPhotoLibrary(videoRecordingOutputURL)
                
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Failed to stop recording")
                viewState = .ready
            } catch {
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Failed to stop recording")
                viewState = .ready
            }
        }
    }
    
    // MARK: - Permissions
    
    private func checkPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
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
                    alert = .info(title: "Video Recording", message: "Video saved to photo library")
                    self.provideSaveSuccessHapticFeedback()
                    
                    // Clean up the temp file
                    try? FileManager.default.removeItem(at: videoURL)
                } else if let error = error {
                    showError(error, message: "Failed to save video")
                }
            }
        }
    }
    
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.provideSaveSuccessHapticFeedback()
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func showError(_ error: Error, message: String) {
        let errorMessage = "\(message): \(error.localizedDescription)"
        print(errorMessage)
        
        alert = .info(title: "Error", message: errorMessage)
    }
    
    private func provideSaveSuccessHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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
