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
    var containerSize: CGSize = .zero
    var displayScale: CGFloat = 1

    public private(set) var capturedPhoto: UIImage?
    var alert: AlertState?

    enum SheetType: String, Identifiable {
        var id: String { rawValue }
        case configSheet
    }

    var presentedSheet: SheetType?
    let controller: DualCameraControlling
    var isSettingsButtonVisible: Bool

    private let photoSaveStrategy: DualCameraPhotoSaveStrategy

    private(set) var flashMode: CameraFlashMode = .off
    var showCameraFlashButton: Bool

    public init(
        dualCameraController: DualCameraControlling? = nil,
        layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        contentMode: DualCameraContentMode = .aspectFill,
        photoSaveStrategy: DualCameraPhotoSaveStrategy = .custom { _ in },
        showSettingsButton: Bool = false,
        showCameraFlashButton: Bool = true
    ) {
        self.controller = dualCameraController ?? CurrentDualCameraEnvironment.dualCameraController
        self.cameraLayout = layout
        self.contentMode = contentMode
        self.photoSaveStrategy = photoSaveStrategy
        self.isSettingsButtonVisible = showSettingsButton
        self.showCameraFlashButton = showCameraFlashButton
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
        try? controller.setTorchMode(.off)
        flashMode = .off
        controller.stopSession()
    }

    func toggleFlashButtonTapped() {
        let nextMode: CameraFlashMode = flashMode == .on ? .off : .on

        do {
            try controller.setTorchMode(nextMode.torchMode)
            flashMode = nextMode
        } catch {
            flashMode = .off
            showError(error, message: "Failed to update flashlight")
        }
    }

    public func containerSizeChanged(_ newSize: CGSize) {
        containerSize = newSize
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
            let image = try await controller.capturePhoto(
                layout: cameraLayout,
                outputSize: containerSize,
                displayScale: displayScale,
                contentMode: contentMode
            )

            capturedPhoto = image
            try await photoSaveStrategy.save(image)
            viewState = .ready
            provideSaveSuccessHapticFeedback()
        } catch let error as DualCameraError {
            viewState = .error(error)
            showError(error, message: "Error capturing photo")
            viewState = .ready
        } catch {
            let dualCameraError = DualCameraError.unknownError
            viewState = .error(dualCameraError)
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

    private func provideSaveSuccessHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

public extension DualCameraViewModel {
    static func `default`() -> DualCameraViewModel {
        DualCameraViewModel(
            dualCameraController: CurrentDualCameraEnvironment.dualCameraController
        )
    }
}

extension CameraViewState {
    var isPhotoButtonEnabled: Bool {
        if case .ready = self { return true }
        return false
    }
}
