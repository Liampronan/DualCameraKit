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
}

@MainActor
@Observable
public final class DualCameraViewModel {
    private(set) var viewState: CameraViewState = .loading
    public var isCameraViewStateCapturing: Bool { viewState.captureInProgress }
    var cameraLayout: DualCameraLayout
    var containerSize: CGSize = .zero

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
        photoSaveStrategy: DualCameraPhotoSaveStrategy = .custom { _ in },
        showSettingsButton: Bool = false,
        showCameraFlashButton: Bool = true
    ) {
        self.controller = dualCameraController ?? CurrentDualCameraEnvironment.dualCameraController
        self.cameraLayout = layout
        self.photoSaveStrategy = photoSaveStrategy
        self.isSettingsButtonVisible = showSettingsButton
        self.showCameraFlashButton = showCameraFlashButton
    }

    public func onAppear(containerSize: CGSize) {
        self.containerSize = containerSize
        startSession()
    }

    func onDisappear() {
        try? controller.setTorchMode(.off)
        controller.stopSession()
    }

    func toggleFlashButtonTapped() {
        flashMode = flashMode == .on ? .off : .on
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

    func capturePhotoButtonTapped() {
        Task {
            guard case .ready = viewState else { return }
            viewState = .capturing

            do {
                if flashMode == .on {
                    try? controller.setTorchMode(.on)
                    try await Task.sleep(for: .seconds(0.25))
                }

                let image = try await controller.capturePhoto(
                    layout: cameraLayout,
                    outputSize: containerSize
                )

                if flashMode == .on {
                    try? controller.setTorchMode(.off)
                }

                capturedPhoto = image
                try await photoSaveStrategy.save(image)
                viewState = .ready
                provideSaveSuccessHapticFeedback()
            } catch let error as DualCameraError {
                try? controller.setTorchMode(.off)
                viewState = .error(error)
                showError(error, message: "Error capturing photo")
                viewState = .ready
            } catch {
                try? controller.setTorchMode(.off)
                let dualCameraError = DualCameraError.unknownError
                viewState = .error(dualCameraError)
                showError(error, message: "Error capturing photo")
                viewState = .ready
            }
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
