import SwiftUI

public struct DualCameraRendererView: UIViewRepresentable {
    private let renderer: CameraRenderer
    
    /// Create renderer view
    public init(renderer: CameraRenderer) {
        self.renderer = renderer
    }
    
    public func makeUIView(context: Context) -> UIView {
        if let metalRenderer = renderer as? MetalCameraRenderer {
            return metalRenderer
        }
        
        // Fallback for non-Metal renderers
        let view = UIView()
        return view
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        // Updates handled by streams
        // TODO: add more explanation here
    }
}
