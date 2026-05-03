import AVFoundation
import DualCameraKit
@testable import DualCameraKitUI
import UIKit
import XCTest

@MainActor
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
    }

    func test_capturePhoto_savesImageAndPublishesCapture() async throws {
        let controller = MockDualCameraController()
        let savedImage = TestBox<UIImage>()
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            photoSaveStrategy: .custom { image in
                await savedImage.set(image)
            }
        )
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        viewModel.capturePhotoButtonTapped()
        try await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(controller.captureOutputSize, CGSize(width: 320, height: 480))
        XCTAssertNotNil(viewModel.capturedPhoto)
        XCTAssertTrue(await savedImage.get() === controller.mockCapturedImage)
        XCTAssertEqual(viewModel.viewState, .ready)
    }

    func test_capturePhoto_failureShowsAlertAndResetsReady() async throws {
        let controller = MockDualCameraController()
        controller.shouldFailCapturePhoto = true
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        viewModel.onAppear(containerSize: CGSize(width: 320, height: 480))
        await Task.yield()

        viewModel.capturePhotoButtonTapped()
        try await Task.sleep(for: .milliseconds(10))

        XCTAssertNil(viewModel.capturedPhoto)
        XCTAssertNotNil(viewModel.alert)
        XCTAssertEqual(viewModel.viewState, .ready)
    }
}

@MainActor
final class MockDualCameraController: DualCameraControlling {
    var sessionStarted = false
    var sessionStopped = false
    var shouldFailStartSession = false
    var shouldFailCapturePhoto = false
    var torchModes: [AVCaptureDevice.TorchMode] = []
    var captureOutputSize: CGSize?
    let mockCapturedImage = UIImage()

    func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
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

    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        (mockCapturedImage, mockCapturedImage)
    }

    func capturePhoto(layout: DualCameraLayout, outputSize: CGSize) async throws -> UIImage {
        if shouldFailCapturePhoto {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        captureOutputSize = outputSize
        return mockCapturedImage
    }

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        torchModes.append(mode)
    }
}

@MainActor
final class MockCameraRenderer: CameraRenderer {
    let view = UIView()

    func update(with buffer: CVPixelBuffer) {}
}
