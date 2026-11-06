import DualCameraKit
@testable import DualCameraKitUI
import SwiftUI
import UIKit
import XCTest

/// Pins the photo capture size to the rect the camera preview actually occupies.
///
/// The preview ignores the safe area, so on a notched iPhone it fills the whole screen. Capture
/// must use that same size. Sizing capture from a safe-area `GeometryReader` produced photos that
/// were shorter than the screen, with the PiP placed above the safe-area bottom, not the screen bottom.
@MainActor
final class DualCameraScreenGeometryTests: XCTestCase {
    /// iPhone 15/16-style portrait screen with a Dynamic Island and home indicator.
    private let screenSize = CGSize(width: 393, height: 852)
    private let notchedSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    func test_displayView_ignoringSafeArea_reportsFullScreenSize() async throws {
        let recorder = SizeRecorder()
        let controller = MockDualCameraController()
        let host = UIHostingController(
            rootView: DualCameraDisplayView(
                controller: controller,
                onDisplaySizeChange: { recorder.sizes.append($0) }
            )
            .ignoresSafeArea()
        )
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil { recorder.sizes.last == self.screenSize }

        assertSafeAreaIsInset(host)
        XCTAssertEqual(recorder.sizes.last, screenSize)
    }

    func test_screen_capturesAtFullScreenSize_withPiPAtScreenBottom() async throws {
        let controller = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: controller)
        let host = UIHostingController(rootView: DualCameraScreen(viewModel: viewModel))
        let window = show(host)
        defer { window.isHidden = true }

        try await waitUntil { viewModel.viewState == .ready && viewModel.containerSize == self.screenSize }

        assertSafeAreaIsInset(host)
        XCTAssertEqual(viewModel.containerSize, screenSize)

        await viewModel.capturePhotoButtonTapped().value

        let outputSize = try XCTUnwrap(controller.captureOutputSize)
        XCTAssertEqual(outputSize, screenSize)

        // Default layout: front mini camera, bottom trailing, 16 pt from the screen edges.
        let pip = try XCTUnwrap(
            DualCameraLayoutResolver().resolve(layout: viewModel.cameraLayout, in: outputSize).overlay
        )
        XCTAssertEqual(pip.source, .front)
        XCTAssertEqual(pip.frame.maxX, screenSize.width - 16, accuracy: 0.001)
        XCTAssertEqual(pip.frame.maxY, screenSize.height - 16, accuracy: 0.001)
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

    private func assertSafeAreaIsInset(
        _ host: UIViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Guards against a false pass: without real insets the safe-area size equals the screen size.
        XCTAssertGreaterThanOrEqual(host.view.safeAreaInsets.top, notchedSafeAreaInsets.top, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            host.view.safeAreaInsets.bottom,
            notchedSafeAreaInsets.bottom,
            file: file,
            line: line
        )
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

@MainActor
private final class SizeRecorder {
    var sizes: [CGSize] = []
}
