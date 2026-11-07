import SwiftUI
import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject, Sendable {
    /// Converts raw front and back pixel buffers into `UIImage` instances.
    func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage)

    /// Composites front and back pixel buffers into a single image matching `layout` and `overlayInsets`.
    func captureComposedPhoto( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage
}

public extension DualCameraPhotoCapturing {
    /// Converts raw front and back pixel buffers into `UIImage` instances at scale `1`.
    func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer
    ) async throws -> (front: UIImage, back: UIImage) {
        try await captureRawPhotos(frontBuffer: frontBuffer, backBuffer: backBuffer, displayScale: 1)
    }

    /// Composites front and back pixel buffers for `layout` and `outputSize` using `.aspectFill` at scale `1`.
    func captureComposedPhoto(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> UIImage {
        try await captureComposedPhoto(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Composites front and back pixel buffers for `layout`, `outputSize`, and `displayScale` using `.aspectFill`.
    func captureComposedPhoto(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat
    ) async throws -> UIImage {
        try await captureComposedPhoto(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Composites front and back pixel buffers for `layout`, `outputSize`, `displayScale`, and `contentMode`.
    func captureComposedPhoto( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage {
        try await captureComposedPhoto(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: EdgeInsets()
        )
    }
}

public class DualCameraPhotoCapturer: DualCameraPhotoCapturing {
    private let layoutResolver: DualCameraLayoutResolver
    /// Creating a `CIContext` is expensive, so one context is shared by every capture.
    private let ciContext = CIContext()

    /// Creates a photo capturer using the given layout resolver.
    public init(layoutResolver: DualCameraLayoutResolver = DualCameraLayoutResolver()) {
        self.layoutResolver = layoutResolver
    }

    /// Converts raw front and back pixel buffers into `UIImage` instances.
    public func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage) {
        return (
            front: try image(from: frontBuffer, displayScale: displayScale),
            back: try image(from: backBuffer, displayScale: displayScale)
        )
    }

    /// Composites front and back pixel buffers into a single image matching `layout` and `overlayInsets`.
    public func captureComposedPhoto( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> UIImage {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DualCameraError.captureFailure(.unknownDimensions)
        }

        let resolvedLayout = layoutResolver.resolve(
            layout: layout,
            in: outputSize,
            overlayInsets: overlayInsets
        )
        let frontImage = try image(from: frontBuffer, displayScale: displayScale)
        let backImage = try image(from: backBuffer, displayScale: displayScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))

            for region in resolvedLayout.regionsInDrawingOrder {
                let image = region.source == .front ? frontImage : backImage
                draw(
                    image,
                    in: region.frame,
                    cornerRadius: cornerRadius(for: region, layout: layout),
                    contentMode: contentMode
                )
            }
        }
    }

    private func image(from buffer: CVPixelBuffer, displayScale: CGFloat) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return UIImage(cgImage: cgImage, scale: displayScale, orientation: .up)
    }

    private func draw(
        _ image: UIImage,
        in targetRect: CGRect,
        cornerRadius: CGFloat,
        contentMode: DualCameraContentMode
    ) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        defer { context?.restoreGState() }

        if cornerRadius > 0 {
            let clipPath = UIBezierPath(roundedRect: targetRect, cornerRadius: cornerRadius)
            clipPath.addClip()
        } else {
            context?.clip(to: targetRect)
        }

        UIColor.black.setFill()
        context?.fill(targetRect)

        image.draw(in: contentRect(for: image.size, in: targetRect, contentMode: contentMode))
    }

    private func cornerRadius(for region: DualCameraResolvedLayout.CameraRegion, layout: DualCameraLayout) -> CGFloat {
        guard case .piP(let miniCamera, _) = layout, region.source == miniCamera else {
            return 0
        }
        return 10
    }

    private func contentRect(
        for sourceSize: CGSize,
        in targetRect: CGRect,
        contentMode: DualCameraContentMode
    ) -> CGRect {
        DualCameraContentGeometry.contentRect(for: sourceSize, in: targetRect, contentMode: contentMode)
    }
}
