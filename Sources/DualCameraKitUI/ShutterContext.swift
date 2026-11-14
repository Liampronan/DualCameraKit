import DualCameraKit
import SwiftUI

/// Type alias matching the `DualCamera*` naming convention for ``ShutterContext``.
public typealias DualCameraShutterContext = ShutterContext

/// State and actions provided to `DualCameraScreen`'s custom shutter view builder.
@MainActor
public struct ShutterContext {
    /// Indicates whether the shutter button is currently enabled and ready to capture.
    public let isEnabled: Bool
    /// Indicates whether a photo capture and save operation is currently in progress.
    public let isCapturing: Bool
    private let captureAction: @MainActor () -> Task<Void, Never>

    /// Creates a shutter context with the current capture state and trigger closure.
    public init(
        isEnabled: Bool,
        isCapturing: Bool,
        capture: @escaping @MainActor () -> Task<Void, Never>
    ) {
        self.isEnabled = isEnabled
        self.isCapturing = isCapturing
        self.captureAction = capture
    }

    /// Triggers a photo capture or retries a pending photo save.
    @discardableResult
    public func capture() -> Task<Void, Never> {
        captureAction()
    }
}

/// The default shutter button rendered by `DualCameraScreen` when no custom shutter builder is provided.
public struct DualCameraDefaultShutterButton: View {
    private let context: ShutterContext

    /// Creates the default dual-camera shutter button for the given ``ShutterContext``.
    public init(context: ShutterContext) {
        self.context = context
    }

    public var body: some View {
        Button {
            context.capture()
        } label: {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding()
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .disabled(!context.isEnabled)
        .accessibilityLabel("Take Photo")
        .accessibilityAddTraits(.isButton)
        .background {
            ShutterAccessibilityMetadataView(
                isEnabled: context.isEnabled,
                isCapturing: context.isCapturing,
                label: "Take Photo"
            )
        }
    }
}

struct ShutterAccessibilityMetadataView: UIViewRepresentable {
    let isEnabled: Bool
    let isCapturing: Bool
    let label: String?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        var traits: UIAccessibilityTraits = [.button]
        if !isEnabled {
            traits.insert(.notEnabled)
        }
        uiView.accessibilityTraits = traits
        uiView.accessibilityLabel = label
        uiView.accessibilityElementsHidden = isCapturing
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

    /// Indicates whether a photo capture and save operation is currently in progress.
    var isCapturing: Bool { viewState.captureInProgress }

    /// Indicates whether the shutter button is enabled in the current camera state.
    var isPhotoButtonEnabled: Bool { viewState.isPhotoButtonEnabled }

    /// Indicates whether photo capture is currently enabled in the current camera state.
    var isCaptureEnabled: Bool { viewState.isPhotoButtonEnabled }

    /// Current shutter state and capture trigger passed to `DualCameraScreen`'s shutter builder.
    var shutterContext: ShutterContext {
        ShutterContext(
            isEnabled: isPhotoButtonEnabled,
            isCapturing: isCapturing,
            capture: { [weak self] in
                guard let self else { return Task {} }
                return self.capturePhotoButtonTapped()
            }
        )
    }

    /// Triggers photo capture (or retries a pending photo save).
    @discardableResult
    func capture() -> Task<Void, Never> {
        capturePhotoButtonTapped()
    }
}

extension DualCameraViewModel {
    /// Updates the measured shutter frame and height reported by `DualCameraScreen`.
    func shutterFrameChanged(_ newFrame: CGRect) {
        guard showsShutterButton else {
            shutterFrame = .zero
            shutterHeight = 0
            return
        }
        shutterFrame = newFrame
        shutterHeight = newFrame.height
    }
}

private struct DualCameraShutterHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = DualCameraViewModel.defaultShutterHeight
}

private struct DualCameraShutterFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

public extension EnvironmentValues {
    /// Height of the built-in shutter control in `DualCameraScreen` (`0` when hidden).
    var dualCameraShutterHeight: CGFloat {
        get { self[DualCameraShutterHeightKey.self] }
        set { self[DualCameraShutterHeightKey.self] = newValue }
    }

    /// Frame of the built-in shutter control in `DualCameraScreen`'s safe-area coordinate space.
    var dualCameraShutterFrame: CGRect {
        get { self[DualCameraShutterFrameKey.self] }
        set { self[DualCameraShutterFrameKey.self] = newValue }
    }
}
