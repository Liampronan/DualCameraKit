import SwiftUI

public struct DualCameraRendererView: UIViewRepresentable {
    private let renderer: CameraRenderer
    private let contentMode: DualCameraContentMode

    /// Create renderer view
    public init(renderer: CameraRenderer, contentMode: DualCameraContentMode = .aspectFill) {
        self.renderer = renderer
        self.contentMode = contentMode
    }

    public func makeUIView(context: Context) -> UIView {
        renderer.cameraContentMode = contentMode
        return renderer.view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        renderer.cameraContentMode = contentMode
        // Updates are driven directly by camera-stream tasks.
    }
}
