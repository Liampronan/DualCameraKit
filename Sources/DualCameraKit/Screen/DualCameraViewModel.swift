import Observation
import Photos
import SwiftUI

public enum CaptureScope: Equatable {
    case fullScreen
    case container
    
    var displayName: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .container: return "Container Only"
        }
    }
    
    func toPhotoCaptureMode(using size: CGSize) -> DualCameraPhotoCaptureMode {
        switch self {
        case .fullScreen:
            return .fullScreen
        case .container:
            return .containerSize(size)
        }
    }
}

public enum DualCameraRecorderType: String, Equatable, CaseIterable, Identifiable {
    case cpuBased = "CPU Recorder"
    case replayKit = "ReplayKit"
    
    public var id: String { rawValue }
    
    public var displayName: String { rawValue }
}

@MainActor
@Observable
public final class DualCameraViewModel {
    
    // Core state
    private(set) var viewState: CameraViewState = .loading
    
    var cameraLayout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    
    // Size tracking
    var containerSize: CGSize = .zero
    
    // Recording configuration
    private(set) var selectedRecorderType: DualCameraRecorderType
    private(set) var selectedCaptureScope: CaptureScope
    
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
    private var videoSaveStrategy: DualCameraVideoSaveStrategy
    private var photoSaveStrategy: DualCameraPhotoSaveStrategy
    
    public init(
        dualCameraController: DualCameraControlling = CurrentDualCameraEnvironment.dualCameraController,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        captureScope: CaptureScope = .fullScreen,
        videoRecorderMode: DualCameraRecorderType = .cpuBased,
        videoSaveStrategy: DualCameraVideoSaveStrategy = .videoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService),
        photoSaveStrategy: DualCameraPhotoSaveStrategy = .photoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService)

    ) {
        self.controller = dualCameraController
        self.cameraLayout = layout
        self.selectedRecorderType = videoRecorderMode
        self.selectedCaptureScope = captureScope
        
        self.videoSaveStrategy = videoSaveStrategy
        self.photoSaveStrategy = photoSaveStrategy
    }
    
    // MARK: - Lifecycle Management
    
    public func onAppear(containerSize: CGSize) {
        self.containerSize = containerSize
        startSession()
    }
    
    private func startSession() {
        print("startSEssion() called")
        Task {
            do {
                viewState = .loading
                try await controller.startSession()
                if Task.isCancelled {
                            print("Task was cancelled before finishing")
                        }
                print("session start!")
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
        // Clean up
        if case .recording = viewState {
            stopRecording()
        }
        controller.stopSession()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Configuration Updates
    
    public func containerSizeChanged(_ newSize: CGSize) {
        self.containerSize = newSize
    }
    
    func updateLayout(_ newLayout: DualCameraLayout) {
        self.cameraLayout = newLayout
    }
    
    func didTapConfigurationButton() {
        if presentedSheet == nil {
            presentedSheet = .configSheet
        }
    }
    
    // MARK: - User Actions
    
    func capturePhotoButtonTapped() {
        Task {
            print("capturePhotoButtonTapped viewSTate", viewState)
            guard case .ready = viewState else { return }
            viewState = .capturing
            
            do {
                try await Task.sleep(for: .seconds(0.25))
                let image = try await controller.captureCurrentScreen(mode: selectedCaptureScope.toPhotoCaptureMode(using: containerSize))
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
        if case .cpuBased = selectedRecorderType {
            selectedRecorderType = .replayKit
        } else {
            selectedRecorderType = .cpuBased
        }
    }
    
    // MARK: - Recording Implementation
    
    private func startRecording() {
        Task {
            viewState = .precapture
            do {
                try await controller.startVideoRecording(mode: effectiveRecorderMode)
                
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
    
    private var effectiveRecorderMode: DualCameraVideoRecordingMode {
        switch selectedRecorderType {
        case .cpuBased:
            return .cpuBased(.init(photoCaptureMode: selectedCaptureScope.toPhotoCaptureMode(using: containerSize)))
        case .replayKit:
            // ReplayKit always uses full screen regardless of selected scope
            return .replayKit()
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
        return DualCameraViewModel(
            dualCameraController: CurrentDualCameraEnvironment.dualCameraController
        )
    }    
}

// MARK: - UI State Helpers

extension CameraViewState {
    // Button state helpers
    var isPhotoButtonEnabled: Bool {
        print("isPhotoButtonEnabled", self)
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
