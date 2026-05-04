import UIKit

@MainActor
public protocol DualCameraPhotoCapturing: AnyObject, Sendable {
    func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage)

    func captureComposedPhoto(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage
}

public extension DualCameraPhotoCapturing {
    func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer
    ) async throws -> (front: UIImage, back: UIImage) {
        try await captureRawPhotos(frontBuffer: frontBuffer, backBuffer: backBuffer, displayScale: 1)
    }

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
            contentMode: .aspectFill
        )
    }

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
            contentMode: .aspectFill
        )
    }
}

public class DualCameraPhotoCapturer: DualCameraPhotoCapturing {
    private let layoutResolver: DualCameraLayoutResolver

    public init(layoutResolver: DualCameraLayoutResolver = DualCameraLayoutResolver()) {
        self.layoutResolver = layoutResolver
    }

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

    public func captureComposedPhoto(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> UIImage {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DualCameraError.captureFailure(.unknownDimensions)
        }

        let resolvedLayout = layoutResolver.resolve(layout: layout, in: outputSize)
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
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
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
        }

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
        guard sourceSize.width > 0, sourceSize.height > 0 else { return targetRect }

        let widthRatio = targetRect.width / sourceSize.width
        let heightRatio = targetRect.height / sourceSize.height
        let scale = switch contentMode {
        case .aspectFill:
            max(widthRatio, heightRatio)
        case .aspectFit:
            min(widthRatio, heightRatio)
        }
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
