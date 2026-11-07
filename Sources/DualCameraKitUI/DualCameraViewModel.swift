import AVFoundation
import DualCameraKit
import Observation
import SwiftUI
import UIKit

/// Flash/torch mode for photo capture.
public enum CameraFlashMode: String, Equatable, CaseIterable {
    case off
    // swiftlint:disable:next identifier_name
    case on

    /// SF Symbol name representing the current flash mode.
    var systemImageName: String {
        switch self {
        case .off: return "bolt.slash.circle.fill"
        case .on: return "bolt.circle.fill"
        }
    }

    /// Corresponding `AVCaptureDevice.TorchMode` value.
    var torchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .on: return .on
        }
    }
}

/// Controls whether photo capture saves only the composed image or both the composed and raw camera images.
public enum DualCameraPhotoOutputMode: String, CaseIterable, Equatable, Sendable, Identifiable {
    /// Saves only the composed image.
    case composedOnly
    /// Saves both the composed image and raw front/back camera images.
    case composedAndRaw

    /// Stable identifier for SwiftUI pickers.
    public var id: String { rawValue }

    /// Human-readable title for UI controls.
    public var title: String {
        switch self {
        case .composedOnly: return "Composed Only"
        case .composedAndRaw: return "Composed + Raw"
        }
    }
}

/// View model managing dual-camera screen state, photo capture, and media persistence.
@MainActor
@Observable
public final class DualCameraViewModel {
    /// Tracks which save stages remain for a captured photo set after a recoverable permission error.
    private struct PendingPhotoSave {
        let photoSet: DualCameraCapturedPhotoSet
        var needsComposedSave: Bool
        var needsFrontRawSave: Bool
        var needsBackRawSave: Bool
        var needsPhotoSetSave: Bool

        var hasRemainingWork: Bool {
            needsComposedSave || needsFrontRawSave || needsBackRawSave || needsPhotoSetSave
        }
    }

    private(set) var viewState: CameraViewState = .loading
    /// Indicates whether a photo capture and save operation is currently in progress.
    public var isCameraViewStateCapturing: Bool { viewState.captureInProgress }
    var cameraLayout: DualCameraLayout
    var contentMode: DualCameraContentMode
    /// Safe-area/overlay insets applied to the preview and composed photo capture.
    public private(set) var overlayInsets: EdgeInsets
    /// Selected photo output persistence mode (`composedOnly` vs `composedAndRaw`).
    public var photoOutputMode: DualCameraPhotoOutputMode
    var containerSize: CGSize = .zero
    var displayScale: CGFloat = 1

    /// Most recently captured composed image.
    public private(set) var capturedPhoto: UIImage?
    /// Most recently captured synchronized photo set containing composed and raw camera images.
    public private(set) var capturedPhotoSet: DualCameraCapturedPhotoSet?
    /// Indicates whether a captured photo set is waiting to retry failed save stages after permission recovery.
    public var hasPendingPhotoSave: Bool { pendingPhotoSave?.hasRemainingWork ?? false }
    var alert: AlertState?

    enum SheetType: String, Identifiable {
        var id: String { rawValue }
        case configSheet
    }

    var presentedSheet: SheetType?
    let controller: DualCameraControlling
    var isSettingsButtonVisible: Bool

    private let photoSaveStrategy: DualCameraPhotoSaveStrategy
    private let photoSetSaveStrategy: DualCameraPhotoSetSaveStrategy?
    private let openSettings: @MainActor () -> Void
    private var pendingPhotoSave: PendingPhotoSave?
    @ObservationIgnored
    private var didBecomeActiveTask: Task<Void, Never>?

    private(set) var flashMode: CameraFlashMode = .off
    var showCameraFlashButton: Bool

    /// Creates a view model with the given camera controller, layout, and save strategies.
    public init(
        dualCameraController: DualCameraControlling? = nil,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        contentMode: DualCameraContentMode = .aspectFill,
        overlayInsets: EdgeInsets = EdgeInsets(),
        photoOutputMode: DualCameraPhotoOutputMode = .composedOnly,
        photoSaveStrategy: DualCameraPhotoSaveStrategy = .custom { _ in },
        photoSetSaveStrategy: DualCameraPhotoSetSaveStrategy? = nil,
        showSettingsButton: Bool = false,
        showCameraFlashButton: Bool = true,
        dependencies: DualCameraDependencies = .live(),
        openSettings: @escaping @MainActor () -> Void = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    ) {
        self.controller = dualCameraController ?? dependencies.dualCameraController
        self.cameraLayout = layout
        self.contentMode = contentMode
        self.overlayInsets = overlayInsets
        self.photoOutputMode = photoOutputMode
        self.photoSaveStrategy = photoSaveStrategy
        self.photoSetSaveStrategy = photoSetSaveStrategy
        self.isSettingsButtonVisible = showSettingsButton
        self.showCameraFlashButton = showCameraFlashButton
        self.openSettings = openSettings
    }

    deinit {
        didBecomeActiveTask?.cancel()
    }

    /// Starts the camera session when the view appears with the given container size and display scale.
    public func onAppear(containerSize: CGSize, displayScale: CGFloat = 1) {
        self.containerSize = containerSize
        self.displayScale = displayScale
        startSession()
    }

    /// Updates the display scale used for rendering captured images.
    public func displayScaleChanged(_ newScale: CGFloat) {
        displayScale = newScale
    }

    /// Stops the camera session and resets the torch when the view disappears.
    func onDisappear() {
        stopObservingAppDidBecomeActiveForPendingSave()
        try? controller.applyTorchMode(.off, for: .back)
        flashMode = .off
        controller.stopSession()
    }

    /// Toggles the rear camera flashlight on or off.
    func toggleFlashButtonTapped() {
        let nextMode: CameraFlashMode = flashMode == .on ? .off : .on
        do {
            let result = try controller.applyTorchMode(nextMode.torchMode, for: .back)
            flashMode = result.wasApplied ? nextMode : .off
        } catch {
            flashMode = .off
            showError(error, message: "Failed to update flashlight")
        }
    }

    /// Updates the container size used for composed photo output.
    public func containerSizeChanged(_ newSize: CGSize) {
        containerSize = newSize
    }

    /// Updates the safe-area/overlay insets used for preview and photo composition.
    public func updateOverlayInsets(_ newInsets: EdgeInsets) {
        overlayInsets = newInsets
    }

    /// Updates the photo output persistence mode (`composedOnly` vs `composedAndRaw`).
    public func updatePhotoOutputMode(_ mode: DualCameraPhotoOutputMode) {
        photoOutputMode = mode
    }

    /// Updates the active dual-camera layout.
    func updateLayout(_ newLayout: DualCameraLayout) {
        cameraLayout = newLayout
    }

    /// Presents the configuration sheet if no sheet is currently presented.
    func didTapConfigurationButton() {
        if presentedSheet == nil {
            presentedSheet = .configSheet
        }
    }

    /// Triggers photo capture (or retries a pending photo save) when the shutter button is tapped.
    @discardableResult
    func capturePhotoButtonTapped() -> Task<Void, Never> {
        Task { await capturePhoto() }
    }

    /// Retries saving the retained photo set for any save stages that previously failed due to permissions.
    public func retryPendingPhotoSave() async {
        guard hasPendingPhotoSave, case .ready = viewState else { return }
        viewState = .capturing
        await performPendingPhotoSave()
    }
}

private extension DualCameraViewModel {
    /// Captures a synchronized photo set or retries an unsaved pending capture before taking a new frame.
    func capturePhoto() async {
        if hasPendingPhotoSave {
            await retryPendingPhotoSave()
            return
        }
        guard case .ready = viewState else { return }
        viewState = .capturing

        do {
            let photoSet = try await controller.capturePhotoSet(
                layout: cameraLayout,
                outputSize: containerSize,
                displayScale: displayScale,
                contentMode: contentMode,
                overlayInsets: overlayInsets
            )
            capturedPhoto = photoSet.composed
            capturedPhotoSet = photoSet
            let shouldSaveRawViaPhotoStrategy = photoOutputMode == .composedAndRaw && photoSetSaveStrategy == nil
            pendingPhotoSave = PendingPhotoSave(
                photoSet: photoSet,
                needsComposedSave: true,
                needsFrontRawSave: shouldSaveRawViaPhotoStrategy,
                needsBackRawSave: shouldSaveRawViaPhotoStrategy,
                needsPhotoSetSave: photoSetSaveStrategy != nil
            )
            await performPendingPhotoSave()
        } catch MediaLibraryError.permissionDenied {
            showPhotoLibraryPermissionDeniedAlert()
            viewState = .ready
        } catch {
            showError(error, message: "Error capturing photo")
            viewState = .ready
        }
    }

    /// Runs any remaining save stages for `pendingPhotoSave`, preserving completed stages if permission fails.
    func performPendingPhotoSave() async {
        guard var pending = pendingPhotoSave else {
            viewState = .ready
            return
        }
        do {
            if pending.needsComposedSave {
                try await photoSaveStrategy.save(pending.photoSet.composed)
                pending.needsComposedSave = false
                pendingPhotoSave = pending
            }
            if pending.needsFrontRawSave {
                try await photoSaveStrategy.save(pending.photoSet.frontRaw)
                pending.needsFrontRawSave = false
                pendingPhotoSave = pending
            }
            if pending.needsBackRawSave {
                try await photoSaveStrategy.save(pending.photoSet.backRaw)
                pending.needsBackRawSave = false
                pendingPhotoSave = pending
            }
            if pending.needsPhotoSetSave, let photoSetSaveStrategy {
                try await photoSetSaveStrategy.save(pending.photoSet)
                pending.needsPhotoSetSave = false
                pendingPhotoSave = pending
            }
            pendingPhotoSave = nil
            stopObservingAppDidBecomeActiveForPendingSave()
            viewState = .ready
            provideSaveSuccessHapticFeedback()
        } catch MediaLibraryError.permissionDenied {
            pendingPhotoSave = pending
            showPhotoLibraryPermissionDeniedAlert()
            viewState = .ready
        } catch {
            pendingPhotoSave = nil
            stopObservingAppDidBecomeActiveForPendingSave()
            showError(error, message: "Error capturing photo")
            viewState = .ready
        }
    }

    /// Starts the underlying camera session asynchronously.
    func startSession() {
        Task {
            do {
                viewState = .loading
                try await controller.startSession()
                viewState = .ready
            } catch is CancellationError {
                return
            } catch let error as DualCameraError {
                viewState = .error(error)
                showError(error, message: "Failed to start camera")
            } catch {
                viewState = .error(.unknownError)
                showError(error, message: "Failed to start camera")
            }
        }
    }

    /// Populates `alert` with a generic error message.
    func showError(_ error: Error, message: String) {
        alert = .info(title: "Error", message: "\(message): \(error.localizedDescription)")
    }

    /// Populates `alert` with a recovery prompt directing the user to Settings when photo library access is denied.
    func showPhotoLibraryPermissionDeniedAlert() {
        let message = [
            MediaLibraryError.permissionDenied.errorDescription,
            MediaLibraryError.permissionDenied.recoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        alert = AlertState(
            title: "Photo Library Access Required",
            message: message,
            primaryButton: AlertState.AlertButton(
                text: "Open Settings",
                action: { [weak self, openSettings] in
                    self?.startObservingAppDidBecomeActiveForPendingSave()
                    openSettings()
                }
            ),
            secondaryButton: AlertState.AlertButton(
                text: "Cancel",
                action: { [weak self] in
                    self?.pendingPhotoSave = nil
                    self?.stopObservingAppDidBecomeActiveForPendingSave()
                }
            )
        )
    }

    /// Observes `UIApplication.didBecomeActiveNotification` to automatically retry a pending photo save after Settings.
    func startObservingAppDidBecomeActiveForPendingSave() {
        stopObservingAppDidBecomeActiveForPendingSave()
        didBecomeActiveTask = Task { @MainActor [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled, let self else { break }
                self.stopObservingAppDidBecomeActiveForPendingSave()
                await self.retryPendingPhotoSave()
                break
            }
        }
    }

    /// Cancels the `UIApplication.didBecomeActiveNotification` observation task if running.
    func stopObservingAppDidBecomeActiveForPendingSave() {
        didBecomeActiveTask?.cancel()
        didBecomeActiveTask = nil
    }

    /// Triggers a success notification haptic after saving completes.
    func provideSaveSuccessHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

public extension DualCameraViewModel {
    /// Creates a default view model using the given dependencies.
    static func `default`(
        dependencies: DualCameraDependencies = .live()
    ) -> DualCameraViewModel {
        DualCameraViewModel(
            dependencies: dependencies
        )
    }
}

extension CameraViewState {
    /// Indicates whether the shutter button should be enabled for the current view state.
    var isPhotoButtonEnabled: Bool {
        if case .ready = self { return true }
        return false
    }
}
