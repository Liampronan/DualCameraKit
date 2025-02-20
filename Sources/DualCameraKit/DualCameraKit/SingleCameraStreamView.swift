import AVFoundation
import SwiftUI

/// Determines where to render with `MetalKit` for GPU rendering or `UIKit` for CPU rendering.
/// Prefer `metal` unless you have a good reason for CPU rendering – metal is more performant.
public enum DualCameraRenderingMode {
    case metal
    case uiImageView
}

/// A SwiftUI-compatible view that renders output from a single pixel buffer (in this case camera).
/// Supports Metal & UIImageView rendering modes.
public struct SingleCameraStreamView {
    public let pixelBufferStream: AsyncStream<CVPixelBuffer>
    public let renderingMode: DualCameraRenderingMode
    
    public init(
        pixelBufferStream: AsyncStream<CVPixelBuffer>,
        renderingMode: DualCameraRenderingMode = .metal
    ) {
        self.pixelBufferStream = pixelBufferStream
        self.renderingMode = renderingMode
    }
}

extension SingleCameraStreamView: UIViewRepresentable {
    public func makeUIView(context: Context) -> UIView {
        switch renderingMode {
        case .metal:
            return MetalCameraRenderer()
        case .uiImageView:
            return UIImageView()
        }
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        switch renderingMode {
        case .metal:
            if let metalView = uiView as? MetalCameraRenderer {
                Task {
                    for await buffer in pixelBufferStream {
                        metalView.update(with: buffer)
                    }
                }
            }
        case .uiImageView:
            if let imageView = uiView as? UIImageView {
                Task {
                    for await buffer in pixelBufferStream {
                        DispatchQueue.main.async {
                            imageView.image = UIImage(ciImage: CIImage(cvPixelBuffer: buffer))
                        }
                    }
                }
            }
        }
    }
}
