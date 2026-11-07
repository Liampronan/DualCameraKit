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

    var systemImageName: String {
        switch self {
        case .off: return "bolt.slash.circle.fill"
        case .on: return "bolt.circle.fill"
        }
    }

    var torchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .on: return .on
        }
    }
}

@MainActor
@Observable
public final class DualCameraViewModel {
    private(set) var viewState: CameraViewState = .loading
    public var isCameraViewStateCapturing: Bool { viewState.captureInProgress }
    var cameraLayout: DualCameraLayout
    var contentMode: DualCameraContentMode
    public private(set) var overlayInsets: EdgeInsets
    var containerSize: CGSize = .zero
    var displayScale: CGFloat = 1

    public private(set) var capturedPhoto: UIImage?
    public private(set) var capturedPhotoSet: DualCameraCapturedPhotoSet?
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

    private(set) var flashMode: CameraFlashMode = .off
    var showCameraFlashButton: Bool

    public init(
        dualCameraController: DualCameraControlling? = nil,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        contentMode: DualCameraContentMode = .aspectFill,
        overlayInsets: EdgeInsets = EdgeInsets(),
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
        self.photoSaveStrategy = photoSaveStrategy
        self.photoSetSaveStrategy = photoSetSaveStrategy
        self.isSettingsButtonVisible = showSettingsButton
        self.showCameraFlashButton = showCameraFlashButton
        self.openSettings = openSettings
    }

    public func onAppear(containerSize: CGSize, displayScale: CGFloat = 1) {
        self.containerSize = containerSize
        self.displayScale = displayScale
        startSession()
    }

    public func displayScaleChanged(_ newScale: CGFloat) {
        displayScale = newScale
    }

    func onDisappear() {
        try? controller.applyTorchMode(.off, for: .back)
        flashMode = .off
        controller.stopSession()
    }

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

    public func containerSizeChanged(_ newSize: CGSize) {
        containerSize = newSize
    }

    public func updateOverlayInsets(_ newInsets: EdgeInsets) {
        overlayInsets = newInsets
    }

    func updateLayout(_ newLayout: DualCameraLayout) {
        cameraLayout = newLayout
    }

    func didTapConfigurationButton() {
        if presentedSheet == nil {
            presentedSheet = .configSheet
        }
    }

    @discardableResult
    func capturePhotoButtonTapped() -> Task<Void, Never> {
        Task {
            await capturePhoto()
        }
    }

    private func capturePhoto() async {
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
            try await photoSaveStrategy.save(photoSet.composed)
            if let photoSetSaveStrategy {
                try await photoSetSaveStrategy.save(photoSet)
            }
            viewState = .ready
            provideSaveSuccessHapticFeedback()
        } catch MediaLibraryError.permissionDenied {
            showPhotoLibraryPermissionDeniedAlert()
            viewState = .ready
        } catch {
            showError(error, message: "Error capturing photo")
            viewState = .ready
        }
    }

    private func startSession() {
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
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Failed to start camera")
            }
        }
    }

    private func showError(_ error: Error, message: String) {
        alert = .info(title: "Error", message: "\(message): \(error.localizedDescription)")
    }

    private func showPhotoLibraryPermissionDeniedAlert() {
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
                action: { [openSettings] in
                    openSettings()
                }
            ),
            secondaryButton: AlertState.AlertButton(text: "Cancel", action: {})
        )
    }

    private func provideSaveSuccessHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

public extension DualCameraViewModel {
    static func `default`(
        dependencies: DualCameraDependencies = .live()
    ) -> DualCameraViewModel {
        DualCameraViewModel(
            dependencies: dependencies
        )
    }
}

extension CameraViewState {
    var isPhotoButtonEnabled: Bool {
        if case .ready = self { return true }
        return false
    }
}
