import DualCameraKit
@testable import DualCameraKitUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DualCameraShutterTests: XCTestCase {
    private let screenSize = CGSize(width: 393, height: 852)
    private let notchedSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    func test_defaultShutter_isEnabledOnlyWhenReady_andTriggersCapture() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)

        // Initially loading
        XCTAssertEqual(viewModel.viewState, .loading)
        XCTAssertFalse(viewModel.isPhotoButtonEnabled)
        XCTAssertFalse(viewModel.isCaptureEnabled)
        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertFalse(viewModel.shutterContext.isEnabled)
        XCTAssertFalse(viewModel.shutterContext.isCapturing)

        let host = UIHostingController(rootView: DualCameraScreen(viewModel: viewModel))
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil { viewModel.viewState == .ready }

        XCTAssertTrue(viewModel.isPhotoButtonEnabled)
        XCTAssertTrue(viewModel.isCaptureEnabled)
        XCTAssertTrue(viewModel.shutterContext.isEnabled)
        XCTAssertFalse(viewModel.shutterContext.isCapturing)

        await viewModel.shutterContext.capture().value

        XCTAssertEqual(controller.captureCount, 1)
        XCTAssertNotNil(viewModel.capturedPhoto)
    }

    func test_shutterState_whileCapturingAndOnError_disablesAndMarksCapturing() async throws {
        let controller = MockDualCameraController()
        controller.pauseCapture = true
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        viewModel.onAppear(containerSize: screenSize)
        try await waitUntil { viewModel.viewState == .ready }

        XCTAssertEqual(viewModel.viewState, .ready)
        XCTAssertTrue(viewModel.isPhotoButtonEnabled)

        let captureTask = viewModel.capture()
        try await waitUntil { viewModel.isCapturing }

        XCTAssertTrue(viewModel.isCapturing)
        XCTAssertTrue(viewModel.isCameraViewStateCapturing)
        XCTAssertFalse(viewModel.isPhotoButtonEnabled)
        XCTAssertFalse(viewModel.isCaptureEnabled)
        XCTAssertTrue(viewModel.shutterContext.isCapturing)
        XCTAssertFalse(viewModel.shutterContext.isEnabled)

        controller.resumeCapture()
        await captureTask.value

        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertTrue(viewModel.isPhotoButtonEnabled)

        // Error state disables shutter
        let failingController = MockDualCameraController()
        failingController.shouldFailStartSession = true
        let errorViewModel = DualCameraViewModel(dualCameraController: failingController)
        errorViewModel.onAppear(containerSize: screenSize)
        try await waitUntil { errorViewModel.viewState == .error(.unknownError) }

        XCTAssertFalse(errorViewModel.isPhotoButtonEnabled)
        XCTAssertFalse(errorViewModel.isCaptureEnabled)
        XCTAssertFalse(errorViewModel.shutterContext.isEnabled)
    }

    func test_customShutterBuilder_rendersStateDependentGlyphAndCaptures() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        let modeModel = ShutterModeTestModel()
        let recorder = ShutterRenderRecorder()

        let screen = DualCameraScreen(
            viewModel: viewModel,
            shutter: { (context: DualCameraShutterContext) in
                CustomModeShutterView(
                    modeModel: modeModel,
                    context: context,
                    recorder: recorder
                )
            }
        )
        let host = UIHostingController(rootView: screen)
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil {
            viewModel.viewState == .ready && recorder.lastIsEnabled == true
        }

        XCTAssertEqual(recorder.lastGlyphName, "camera.fill")
        XCTAssertEqual(recorder.lastIsEnabled, true)
        XCTAssertEqual(recorder.lastIsCapturing, false)

        // Swap app state and verify custom shutter updates its glyph without recreating DualCameraScreen
        modeModel.isCallItIn = true
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await waitUntil { recorder.lastGlyphName == "megaphone.fill" }
        XCTAssertEqual(recorder.lastGlyphName, "megaphone.fill")

        // Trigger capture from the custom shutter's latest context
        let context = try XCTUnwrap(recorder.lastContext)
        await context.capture().value
        XCTAssertEqual(controller.captureCount, 1)
    }

    func test_shutterAccessibility_exposesButtonTraitOnDefaultAndCustomShutter() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            showCameraFlashButton: false
        )
        let defaultHost = UIHostingController(rootView: DualCameraScreen(viewModel: viewModel))
        let window = show(defaultHost)
        defer { window.isHidden = true }

        try await waitUntil { viewModel.viewState == .ready }
        defaultHost.view.layoutIfNeeded()
        let defaultShutter = try XCTUnwrap(
            findAccessibleElement(withIdentifier: "dualCamera.shutterButton", in: defaultHost.view)
        )
        XCTAssertTrue(defaultShutter.isAccessibilityElement)
        XCTAssertTrue(defaultShutter.accessibilityTraits.contains(.button))
        XCTAssertFalse(defaultShutter.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(defaultShutter.accessibilityActivate())
        try await waitUntil { controller.captureCount == 1 }

        let customScreen = DualCameraScreen(
            viewModel: viewModel,
            shutter: { context in
                Text("Custom Shutter")
                    .onTapGesture {
                        context.capture()
                    }
            }
        )
        let customHost = UIHostingController(rootView: customScreen)
        let customWindow = show(customHost)
        defer { customWindow.isHidden = true }

        customHost.view.layoutIfNeeded()
        let customShutter = try XCTUnwrap(
            findAccessibleElement(withIdentifier: "dualCamera.shutterButton", in: customHost.view)
        )
        XCTAssertTrue(customShutter.isAccessibilityElement)
        XCTAssertTrue(customShutter.accessibilityTraits.contains(.button))
        XCTAssertTrue(customShutter.accessibilityActivate())
        try await waitUntil { controller.captureCount == 2 }
    }

    func test_shutterLayoutMetrics_reportsMeasuredFrameAndHeightAndEnvironmentValues() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        let overlayRecorder = OverlayMetricsRecorder()

        XCTAssertEqual(viewModel.shutterHeight, DualCameraViewModel.defaultShutterHeight)
        XCTAssertEqual(viewModel.shutterFrame, .zero)

        let screen = DualCameraScreen(viewModel: viewModel) { _ in
            OverlayProbeView(recorder: overlayRecorder)
        }
        let host = UIHostingController(rootView: screen)
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil {
            viewModel.viewState == .ready &&
                viewModel.shutterFrame.height > 0 &&
                overlayRecorder.envFrame.height > 0
        }

        XCTAssertGreaterThan(viewModel.shutterHeight, 0)
        XCTAssertGreaterThan(viewModel.shutterFrame.width, 0)
        XCTAssertEqual(viewModel.shutterHeight, viewModel.shutterFrame.height, accuracy: 0.001)
        XCTAssertEqual(overlayRecorder.envHeight, viewModel.shutterHeight, accuracy: 0.001)
        XCTAssertEqual(overlayRecorder.envFrame, viewModel.shutterFrame)
    }

    func test_showsShutterButtonFalse_hidesBuiltInShutterAndAllowsPublicCapture() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            showsShutterButton: false
        )
        let shutterRenderCount = ShutterRenderRecorder()

        XCTAssertFalse(viewModel.showsShutterButton)
        XCTAssertEqual(viewModel.shutterHeight, 0)
        XCTAssertEqual(viewModel.shutterFrame, .zero)

        let screen = DualCameraScreen(
            viewModel: viewModel,
            shutter: { context in
                Button {
                    context.capture()
                } label: {
                    Text("Custom")
                }
                .onAppear {
                    shutterRenderCount.renderCount += 1
                }
            }
        )
        let host = UIHostingController(rootView: screen)
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil { viewModel.viewState == .ready }
        host.view.layoutIfNeeded()

        XCTAssertEqual(shutterRenderCount.renderCount, 0)
        XCTAssertEqual(viewModel.shutterHeight, 0)
        XCTAssertEqual(viewModel.shutterFrame, .zero)

        // Public capture() works when built-in shutter is hidden
        await viewModel.capture().value
        XCTAssertEqual(controller.captureCount, 1)

        // Re-enabling showsShutterButton restores measurement
        viewModel.showsShutterButton = true
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await waitUntil { viewModel.shutterFrame.height > 0 }
        XCTAssertGreaterThan(viewModel.shutterHeight, 0)

        // Disabling again resets metrics to zero
        viewModel.showsShutterButton = false
        XCTAssertEqual(viewModel.shutterHeight, 0)
        XCTAssertEqual(viewModel.shutterFrame, .zero)
    }

    // MARK: - Helpers

    private func show(_ host: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow()
        }
        window.frame = CGRect(origin: .zero, size: screenSize)
        host.additionalSafeAreaInsets = notchedSafeAreaInsets
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    private func findAccessibleElement(
        withIdentifier identifier: String,
        in view: UIView
    ) -> UIView? {
        guard !view.isHidden, !view.accessibilityElementsHidden, view.alpha > 0.01 else {
            return nil
        }
        if view.isAccessibilityElement, view.accessibilityIdentifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = findAccessibleElement(withIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Condition not met within \(timeout)", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Observable
@MainActor
private final class ShutterModeTestModel {
    var isCallItIn = false
}

@MainActor
private final class ShutterRenderRecorder {
    var renderCount = 0
    var lastGlyphName: String?
    var lastIsEnabled: Bool?
    var lastIsCapturing: Bool?
    var lastContext: ShutterContext?
}

private struct CustomModeShutterView: View {
    let modeModel: ShutterModeTestModel
    let context: ShutterContext
    let recorder: ShutterRenderRecorder

    var body: some View {
        let glyph = modeModel.isCallItIn ? "megaphone.fill" : "camera.fill"
        _ = record(glyph: glyph)
        return Button {
            context.capture()
        } label: {
            Image(systemName: glyph)
                .font(.largeTitle)
                .padding(20)
                .background(Circle().fill(modeModel.isCallItIn ? Color.white : Color.purple))
        }
    }

    @MainActor
    private func record(glyph: String) {
        recorder.renderCount += 1
        recorder.lastGlyphName = glyph
        recorder.lastIsEnabled = context.isEnabled
        recorder.lastIsCapturing = context.isCapturing
        recorder.lastContext = context
    }
}

@MainActor
private final class OverlayMetricsRecorder {
    var envHeight: CGFloat = 0
    var envFrame: CGRect = .zero
}

private struct OverlayProbeView: View {
    @Environment(\.dualCameraShutterHeight) private var envHeight
    @Environment(\.dualCameraShutterFrame) private var envFrame
    let recorder: OverlayMetricsRecorder

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onChange(of: envHeight, initial: true) { _, newValue in
                recorder.envHeight = newValue
            }
            .onChange(of: envFrame, initial: true) { _, newValue in
                recorder.envFrame = newValue
            }
    }
}
