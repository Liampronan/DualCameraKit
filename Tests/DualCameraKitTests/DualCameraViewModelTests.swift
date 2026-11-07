// swiftlint:disable file_length
import AVFoundation
import DualCameraKit
@testable import DualCameraKitUI
import SwiftUI
import UIKit
import XCTest

@MainActor
// swiftlint:disable:next type_body_length
final class DualCameraViewModelTests: XCTestCase {
    func test_init_withDefaultParams_setsDefaultValues() {
        let viewModel = DualCameraViewModel(dualCameraController: MockDualCameraController())

        XCTAssertEqual(viewModel.viewState, .loading)
        XCTAssertEqual(viewModel.cameraLayout, .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing))
    }

    func test_init_withCustomParams_setsCustomValues() {
        let controller = MockDualCameraController()
        let customLayout: DualCameraLayout = .sideBySide

        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            layout: customLayout
        )

        XCTAssertEqual(viewModel.cameraLayout, customLayout)
        XCTAssertIdentical(viewModel.controller as? MockDualCameraController, controller)
    }

    func test_init_usesExplicitDependenciesWhenControllerIsNotProvided() {
        let controller = MockDualCameraController()
        let dependencies = DualCameraDependencies(
            mediaLibraryService: .noop,
            dualCameraController: controller
        )

        let viewModel = DualCameraViewModel(dependencies: dependencies)

        XCTAssertIdentical(viewModel.controller as? MockDualCameraController, controller)
    }

    func test_onAppear_startsSession() async {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        await Task.yield()

        XCTAssertTrue(controller.sessionStarted)
        XCTAssertEqual(viewModel.containerSize, CGSize(width: 390, height: 844))
        XCTAssertEqual(viewModel.viewState, .ready)
    }

    func test_onAppear_handlesError() async {
        let controller = MockDualCameraController()
        controller.shouldFailStartSession = true
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        await Task.yield()

        XCTAssertEqual(viewModel.viewState, .error(DualCameraError.unknownError))
        XCTAssertNotNil(viewModel.alert)
    }

    func test_onDisappear_stopsSessionAndTurnsOffTorch() async {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        await Task.yield()
        viewModel.onDisappear()

        XCTAssertTrue(controller.sessionStopped)
        XCTAssertEqual(controller.torchModes, [.off])
        XCTAssertEqual(viewModel.flashMode, .off)
    }

    func test_toggleFlashButtonTapped_setsTorchImmediately() {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.toggleFlashButtonTapped()

        XCTAssertEqual(viewModel.flashMode, .on)
        XCTAssertEqual(controller.torchModes, [.on])

        viewModel.toggleFlashButtonTapped()

        XCTAssertEqual(viewModel.flashMode, .off)
        XCTAssertEqual(controller.torchModes, [.on, .off])
    }

    func test_toggleFlashButtonTapped_whenTorchFailsShowsAlertAndKeepsFlashOff() {
        let controller = MockDualCameraController()
        controller.shouldFailSetTorchMode = true
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.toggleFlashButtonTapped()

        XCTAssertEqual(viewModel.flashMode, .off)
        XCTAssertNotNil(viewModel.alert)
    }

    func test_toggleFlashButtonTapped_whenTorchUnsupportedKeepsFlashOffWithoutAlert() {
        let controller = MockDualCameraController()
        controller.torchModeResult = .unsupported
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        viewModel.toggleFlashButtonTapped()

        XCTAssertEqual(viewModel.flashMode, .off)
        XCTAssertNil(viewModel.alert)
    }

    func test_capturePhoto_savesImageAndPublishesCapture() async throws {
        let controller = MockDualCameraController()
        let savedImage = TestBox<UIImage>()
        let savedPhotoSet = TestBox<DualCameraCapturedPhotoSet>()
        let customInsets = EdgeInsets(top: 48, leading: 16, bottom: 34, trailing: 16)
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            overlayInsets: customInsets,
            photoSaveStrategy: .custom { image in
                await savedImage.set(image)
            },
            photoSetSaveStrategy: .custom { photoSet in
                await savedPhotoSet.set(photoSet)
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480), displayScale: 3)
        await Task.yield()

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        XCTAssertEqual(controller.captureOutputSize, CGSize(width: 320, height: 480))
        XCTAssertEqual(controller.captureDisplayScale, 3)
        XCTAssertEqual(controller.captureContentMode, .aspectFill)
        XCTAssertEqual(controller.captureOverlayInsets, customInsets)
        XCTAssertNotNil(viewModel.capturedPhoto)
        XCTAssertEqual(viewModel.capturedPhotoSet, controller.mockCapturedPhotoSet)
        let savedCapturedImage = await savedImage.get()
        XCTAssertTrue(savedCapturedImage === controller.mockCapturedImage)
        let savedSet = await savedPhotoSet.get()
        XCTAssertEqual(savedSet, controller.mockCapturedPhotoSet)
        XCTAssertEqual(viewModel.viewState, .ready)
    }

    func test_updateOverlayInsets_updatesPublishedOverlayInsetsAndForwardsToCapture() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        let newInsets = EdgeInsets(top: 100, leading: 8, bottom: 80, trailing: 8)
        viewModel.updateOverlayInsets(newInsets)
        XCTAssertEqual(viewModel.overlayInsets, newInsets)

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        XCTAssertEqual(controller.captureOverlayInsets, newInsets)
    }

    func test_capturePhoto_permissionDeniedDuringSaveKeepsCapturedPhotoSetAndShowsRecoveryAlert() async throws {
        let controller = MockDualCameraController()
        var didOpenSettings = false
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            photoSaveStrategy: .custom { _ in
                throw MediaLibraryError.permissionDenied
            },
            openSettings: {
                didOpenSettings = true
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        XCTAssertTrue(viewModel.capturedPhoto === controller.mockCapturedImage)
        XCTAssertEqual(viewModel.capturedPhotoSet, controller.mockCapturedPhotoSet)
        XCTAssertEqual(viewModel.viewState, .ready)

        let alert = try XCTUnwrap(viewModel.alert)
        XCTAssertEqual(alert.title, "Photo Library Access Required")
        let expectedMessage = "Photo library access is required to save photos. " +
            "Please grant photo library access in Settings to save photos."
        XCTAssertEqual(alert.message, expectedMessage)
        XCTAssertEqual(alert.primaryButton.text, "Open Settings")
        XCTAssertEqual(alert.secondaryButton?.text, "Cancel")

        alert.primaryButton.action()
        XCTAssertTrue(didOpenSettings)
    }

    func test_retryPendingPhotoSave_skipsCompletedStageAndRetriesFailedStage() async throws {
        let controller = MockDualCameraController()
        let composedSaveCount = TestBox<Int>()
        await composedSaveCount.set(0)
        let photoSetSaveCount = TestBox<Int>()
        await photoSetSaveCount.set(0)
        let shouldDenyPhotoSetSave = TestBox<Bool>()
        await shouldDenyPhotoSetSave.set(true)

        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            photoSaveStrategy: .custom { _ in
                let current = await composedSaveCount.get() ?? 0
                await composedSaveCount.set(current + 1)
            },
            photoSetSaveStrategy: .custom { _ in
                let count = await photoSetSaveCount.get() ?? 0
                await photoSetSaveCount.set(count + 1)
                if await shouldDenyPhotoSetSave.get() == true {
                    throw MediaLibraryError.permissionDenied
                }
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        // First shutter tap: composed save succeeds, photoSet save fails with permissionDenied.
        let firstTask = viewModel.capturePhotoButtonTapped()
        await firstTask.value

        XCTAssertTrue(viewModel.hasPendingPhotoSave)
        XCTAssertEqual(controller.captureCount, 1)
        let firstComposedCount = await composedSaveCount.get()
        let firstSetCount = await photoSetSaveCount.get()
        XCTAssertEqual(firstComposedCount, 1)
        XCTAssertEqual(firstSetCount, 1)

        // Grant permission and tap shutter again while pending: retries only the failed stage without new capture.
        await shouldDenyPhotoSetSave.set(false)
        let retryTask = viewModel.capturePhotoButtonTapped()
        await retryTask.value

        XCTAssertFalse(viewModel.hasPendingPhotoSave)
        XCTAssertEqual(controller.captureCount, 1)
        let finalComposedCount = await composedSaveCount.get()
        let finalSetCount = await photoSetSaveCount.get()
        XCTAssertEqual(finalComposedCount, 1)
        XCTAssertEqual(finalSetCount, 2)
    }

    func test_permissionDeniedCancelClearsPendingSaveSoNextCaptureTakesNewPhoto() async throws {
        let controller = MockDualCameraController()
        let shouldDeny = TestBox<Bool>()
        await shouldDeny.set(true)

        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            photoSaveStrategy: .custom { _ in
                if await shouldDeny.get() == true {
                    throw MediaLibraryError.permissionDenied
                }
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        let firstTask = viewModel.capturePhotoButtonTapped()
        await firstTask.value
        XCTAssertTrue(viewModel.hasPendingPhotoSave)
        XCTAssertEqual(controller.captureCount, 1)

        let alert = try XCTUnwrap(viewModel.alert)
        alert.secondaryButton?.action()
        XCTAssertFalse(viewModel.hasPendingPhotoSave)

        await shouldDeny.set(false)
        let secondTask = viewModel.capturePhotoButtonTapped()
        await secondTask.value
        XCTAssertEqual(controller.captureCount, 2)
    }

    func test_photoOutputMode_composedAndRawSavesComposedAndRawImagesWhenPhotoSetStrategyIsNil() async throws {
        let controller = MockDualCameraController()
        let savedImages = TestBox<[UIImage]>()
        await savedImages.set([])

        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            photoOutputMode: .composedOnly,
            photoSaveStrategy: .custom { image in
                var current = await savedImages.get() ?? []
                current.append(image)
                await savedImages.set(current)
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        viewModel.updatePhotoOutputMode(.composedAndRaw)
        XCTAssertEqual(viewModel.photoOutputMode, .composedAndRaw)

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        let saved = await savedImages.get()
        let images = try XCTUnwrap(saved)
        XCTAssertEqual(images.count, 3)
        XCTAssertTrue(images[0] === controller.mockCapturedImage)
        XCTAssertTrue(images[1] === controller.mockFrontRawImage)
        XCTAssertTrue(images[2] === controller.mockBackRawImage)
    }

    func test_capturePhoto_failureShowsAlertAndResetsReady() async throws {
        let controller = MockDualCameraController()
        controller.shouldFailCapturePhoto = true
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        XCTAssertNil(viewModel.capturedPhoto)
        XCTAssertNil(viewModel.capturedPhotoSet)
        XCTAssertNotNil(viewModel.alert)
        XCTAssertEqual(viewModel.viewState, .ready)
    }

    func test_capturePhoto_whenFlashlightEnabledDoesNotToggleTorchDuringCapture() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()
        viewModel.toggleFlashButtonTapped()

        let captureTask = viewModel.capturePhotoButtonTapped()
        await captureTask.value

        XCTAssertEqual(controller.torchModes, [.on])
        XCTAssertEqual(viewModel.flashMode, .on)
        XCTAssertNotNil(viewModel.capturedPhoto)
    }
}

@MainActor
final class MockDualCameraController: DualCameraControlling {
    var sessionStarted = false
    var sessionStopped = false
    var shouldFailStartSession = false
    var shouldFailCapturePhoto = false
    var shouldFailSetTorchMode = false
    var torchModeResult: DualCameraCameraControlResult = .applied
    var torchModes: [AVCaptureDevice.TorchMode] = []
    var captureOutputSize: CGSize?
    var captureDisplayScale: CGFloat?
    var captureContentMode: DualCameraContentMode?
    var captureOverlayInsets: EdgeInsets?
    var captureCount = 0
    let mockCapturedImage = UIImage()
    let mockFrontRawImage = UIImage()
    let mockBackRawImage = UIImage()
    lazy var mockCapturedPhotoSet = DualCameraCapturedPhotoSet(
        composed: mockCapturedImage,
        frontRaw: mockFrontRawImage,
        backRaw: mockBackRawImage
    )

    func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func getRenderer(for source: DualCameraSource) -> CameraRenderer {
        MockCameraRenderer()
    }

    func startSession() async throws {
        if shouldFailStartSession {
            throw DualCameraError.unknownError
        }
        sessionStarted = true
    }

    func stopSession() {
        sessionStopped = true
    }

    func captureRawPhotos(displayScale: CGFloat) async throws -> (front: UIImage, back: UIImage) {
        (mockFrontRawImage, mockBackRawImage)
    }

    func capturePhoto(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        if shouldFailCapturePhoto {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        captureOutputSize = outputSize
        captureDisplayScale = displayScale
        captureContentMode = contentMode
        captureOverlayInsets = overlayInsets
        return mockCapturedImage
    }

    func capturePhotoSet(
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        if shouldFailCapturePhoto {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        captureCount += 1
        captureOutputSize = outputSize
        captureDisplayScale = displayScale
        captureContentMode = contentMode
        captureOverlayInsets = overlayInsets
        return mockCapturedPhotoSet
    }

    func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities {
        .unavailable(for: source)
    }

    @discardableResult
    func applyTorchMode(
        _ mode: AVCaptureDevice.TorchMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        if shouldFailSetTorchMode {
            throw DualCameraError.configurationFailed
        }
        torchModes.append(mode)
        return torchModeResult
    }

    @discardableResult
    func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyFocusMode(
        _ mode: AVCaptureDevice.FocusMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyExposureMode(
        _ mode: AVCaptureDevice.ExposureMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    @discardableResult
    func applyWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        .applied
    }

    func diagnosticsSnapshot() -> DualCameraDiagnostics {
        DualCameraDiagnostics()
    }

}

@MainActor
final class MockCameraRenderer: CameraRenderer {
    let view = UIView()
    var cameraContentMode: DualCameraContentMode = .aspectFill

    nonisolated func update(with frame: PixelBufferWrapper) {}
}
