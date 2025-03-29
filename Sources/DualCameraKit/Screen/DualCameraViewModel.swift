import Observation
import Photos
import SwiftUI

@MainActor
@Observable
public final class DualCameraViewModel {
    
    // Core state
    private(set) var viewState: CameraViewState = .loading
    
    // Configuration
    var configuration: CameraConfiguration
    var videoRecorderType: DualCameraVideoRecordingMode { configuration.videoRecorderMode }
    
    // User artifacts
    private(set) var capturedImage: UIImage? = nil
    var alert: AlertState? = nil
    
    enum SheetType: String, Identifiable {
        var id: String { self.rawValue }
        case configSheet
    }
    var presentedSheet: SheetType?
    
    let controller: DualCameraControlling
    private var recordingTimer: Timer?
    private var videoSaveStrategy: VideoSaveStrategy
    private var photoSaveStrategy: PhotoSaveStrategy
    
    init(
        dualCameraController: DualCameraControlling,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        videoRecorderMode: DualCameraVideoRecordingMode = .cpuBased(.init(photoCaptureMode: .fullScreen)),
        videoSaveStrategy: VideoSaveStrategy = .videoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService),
        photoSaveStrategy: PhotoSaveStrategy = .photoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService)

    ) {
        self.controller = dualCameraController
        self.configuration = CameraConfiguration(
            layout: layout,
            videoRecorderMode: videoRecorderMode
        )
        self.videoSaveStrategy = videoSaveStrategy
        self.photoSaveStrategy = photoSaveStrategy
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
    
    func updateLayout(_ newLayout: DualCameraLayout) {
        configuration.layout = newLayout
    }
    
    func didTapConfigurationButton() {
        if presentedSheet == nil {
            presentedSheet = .configSheet
        }
    }
    
    // MARK: - User Actions
    
    func capturePhotoButtonTapped() {
        Task {
            guard case .ready = viewState else { return }
            viewState = .capturing
            
            do {
                try await Task.sleep(for: .seconds(0.25))
                let image = try await controller.captureCurrentScreen()
                viewState = .ready
                try await self.photoSaveStrategy.save(image)
                self.provideSaveSuccessHapticFeedback()
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
    
    func recordVideoButtonTapped() {
        if case .recording = viewState {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func toggleRecorderType() {
        if case .cpuBased = configuration.videoRecorderMode {
            configuration.videoRecorderMode = .replayKit()
        } else {
            configuration.videoRecorderMode = .cpuBased(.init(photoCaptureMode: .fullScreen))
        }
    }
    
    // MARK: - Recording Implementation
    
    private func startRecording() {
        Task {
            viewState = .precapture
            do {
                try await controller.startVideoRecording(mode: configuration.videoRecorderMode)
                
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

                try await self.videoSaveStrategy.save(videoRecordingOutputURL)
                self.provideSaveSuccessHapticFeedback()
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

// MARK: - Default init 

extension DualCameraViewModel {
    public static func `default`() -> DualCameraViewModel {
        #if targetEnvironment(simulator)
        let dualCameraController = DualCameraMockController()
        #else
        let dualCameraController = DualCameraController()
        #endif

        return DualCameraViewModel(
            dualCameraController: dualCameraController
        )
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
