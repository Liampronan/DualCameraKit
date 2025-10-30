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
    
    func toPhotoCaptureMode(using frame: CGRect) -> DualCameraPhotoCaptureMode {
        switch self {
        case .fullScreen:
            return .fullScreen
        case .container:
            return .containerFrame(frame)
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
    public var isCameraViewStateCapturing: Bool { viewState.captureInProgress }
    var cameraLayout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    
    // Size and position tracking
    var containerSize: CGSize = .zero
    /// The frame of the DualCameraScreen view in global window coordinates.
    /// Used for container-mode capture to crop the screenshot to the visible camera area.
    var containerFrame: CGRect = .zero
    
    // Recording configuration
    private(set) var selectedRecorderType: DualCameraRecorderType
    private(set) var selectedCaptureScope: CaptureScope
    
    // User artifacts - exposed for consumers to observe
    /// The most recently captured photo. Consumers should use `.onChange(of:)` to observe new captures.
    public private(set) var capturedPhoto: UIImage? = nil
    /// The most recently recorded video URL. Consumers should use `.onChange(of:)` to observe new recordings.
    public private(set) var capturedVideo: URL? = nil
    var alert: AlertState? = nil

    enum SheetType: String, Identifiable {
        var id: String { self.rawValue }
        case configSheet
    }
    var presentedSheet: SheetType?

    let controller: DualCameraControlling
    private let saveToLibrary: Bool
    var isVideoButtonVisible: Bool { includeVideoRecording }
    var isSettingsButtonVisible: Bool

    private var recordingTimer: Timer?
    private let includeVideoRecording: Bool
    private let mediaLibraryService: MediaLibraryService
    
    public init(
        dualCameraController: DualCameraControlling = CurrentDualCameraEnvironment.dualCameraController,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        captureScope: CaptureScope = .fullScreen,
        videoRecorderMode: DualCameraRecorderType = .cpuBased,
        includeVideoRecording: Bool = true,
        saveToLibrary: Bool = true,
        mediaLibraryService: MediaLibraryService = CurrentDualCameraEnvironment.mediaLibraryService,
        showSettingsButton: Bool = false
    ) {
        self.controller = dualCameraController
        self.cameraLayout = layout
        self.selectedRecorderType = videoRecorderMode
        self.selectedCaptureScope = captureScope
        self.includeVideoRecording = includeVideoRecording
        self.saveToLibrary = saveToLibrary
        self.mediaLibraryService = mediaLibraryService
        self.isSettingsButtonVisible = showSettingsButton
    }
    
    // MARK: - Lifecycle Management
    
    public func onAppear(containerSize: CGSize) {
        self.containerSize = containerSize
        // Initialize frame with size at origin (will be updated by PreferenceKey with actual position)
        if self.containerFrame == .zero {
            self.containerFrame = CGRect(origin: .zero, size: containerSize)
        }
        startSession()
    }
    
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
        // Update frame size while preserving origin (if already set)
        if containerFrame != .zero {
            self.containerFrame = CGRect(origin: containerFrame.origin, size: newSize)
        } else {
            self.containerFrame = CGRect(origin: .zero, size: newSize)
        }
    }

    /// Updates the container frame when the view's position or size changes in the window.
    /// This is automatically called by DualCameraScreen's GeometryReader.
    /// - Parameter newFrame: The new frame in global window coordinates
    public func containerFrameChanged(_ newFrame: CGRect) {
        self.containerFrame = newFrame
        self.containerSize = newFrame.size
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
            guard case .ready = viewState else { return }
            viewState = .capturing

            do {
                try await Task.sleep(for: .seconds(0.25))
                let image = try await controller.captureCurrentScreen(mode: selectedCaptureScope.toPhotoCaptureMode(using: containerFrame))
                viewState = .ready

                // Expose captured photo for consumers to observe
                self.capturedPhoto = image

                // Optionally save to library
                if saveToLibrary {
                    try await mediaLibraryService.saveImage(image)
                }

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

                // Expose captured video for consumers to observe
                self.capturedVideo = videoRecordingOutputURL

                // Optionally save to library
                if saveToLibrary {
                    try await mediaLibraryService.saveVideo(videoRecordingOutputURL)
                }

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
            return .cpuBased(.init(photoCaptureMode: selectedCaptureScope.toPhotoCaptureMode(using: containerFrame)))
        case .replayKit:
            // ReplayKit always uses full screen regardless of selected scope
            return .replayKit()
        }
    }
    
    // MARK: - Error Handling
    
    private func showError(_ error: Error, message: String) {
        let errorMessage = "\(message): \(error.localizedDescription)"
        
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
