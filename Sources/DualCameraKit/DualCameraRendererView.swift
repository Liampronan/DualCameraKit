import SwiftUI

public struct DualCameraRendererView: UIViewRepresentable {
    private let renderer: CameraRenderer

    /// Create renderer view
    public init(renderer: CameraRenderer) {
        self.renderer = renderer
    }

    public func makeUIView(context: Context) -> UIView {
        renderer.view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // Updates are driven directly by camera-stream tasks.
    }
}
