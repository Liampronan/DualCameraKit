import SwiftUI
import UIKit

/// A synchronized capture result containing the composed image alongside both raw camera images.
public struct DualCameraCapturedPhotoSet: Sendable, Equatable {
    /// Composed image combining front and back camera feeds according to the active layout.
    public let composed: UIImage
    /// Raw decoded image from the front camera.
    public let frontRaw: UIImage
    /// Raw decoded image from the back camera.
    public let backRaw: UIImage

    /// Creates a captured photo set with the composed image and raw front/back camera images.
    public init(composed: UIImage, frontRaw: UIImage, backRaw: UIImage) {
        self.composed = composed
        self.frontRaw = frontRaw
        self.backRaw = backRaw
    }
}

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

    /// Captures raw front/back images and composites them into a single photo set from the same frame pair.
    func capturePhotoSet( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet
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

    /// Captures raw front/back images and composites them into a photo set from the same frame pair.
    func capturePhotoSet( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        let rawPhotos = try await captureRawPhotos(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            displayScale: displayScale
        )
        let composed = try await captureComposedPhoto(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        )
        return DualCameraCapturedPhotoSet(
            composed: composed,
            frontRaw: rawPhotos.front,
            backRaw: rawPhotos.back
        )
    }

    /// Captures a photo set for `layout` and `outputSize` using `.aspectFill` at scale `1`.
    func capturePhotoSet(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, and `displayScale` using `.aspectFill`.
    func capturePhotoSet(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: .aspectFill,
            overlayInsets: EdgeInsets()
        )
    }

    /// Captures a photo set for `layout`, `outputSize`, `displayScale`, and `contentMode`.
    func capturePhotoSet( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode
    ) async throws -> DualCameraCapturedPhotoSet {
        try await capturePhotoSet(
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
    private nonisolated let layoutResolver: DualCameraLayoutResolver
    /// Creating a `CIContext` is expensive, so one thread-safe context is shared by every capture.
    private nonisolated let ciContext = CIContext()

    /// Creates a photo capturer using the given layout resolver.
    public init(layoutResolver: DualCameraLayoutResolver = DualCameraLayoutResolver()) {
        self.layoutResolver = layoutResolver
    }

    /// Converts raw front and back pixel buffers into `UIImage` instances off the main actor.
    public func captureRawPhotos(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage) {
        let frontWrapper = PixelBufferWrapper(buffer: frontBuffer)
        let backWrapper = PixelBufferWrapper(buffer: backBuffer)
        return try await decodeRawPhotosOffMainActor(
            frontWrapper: frontWrapper,
            backWrapper: backWrapper,
            displayScale: displayScale
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
        try await capturePhotoSet(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        ).composed
    }

    /// Decodes raw front/back images once and composites them into a photo set off the main actor.
    public func capturePhotoSet( // swiftlint:disable:this function_parameter_count
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DualCameraError.captureFailure(.unknownDimensions)
        }

        let frontWrapper = PixelBufferWrapper(buffer: frontBuffer)
        let backWrapper = PixelBufferWrapper(buffer: backBuffer)
        return try await renderPhotoSetOffMainActor(
            frontWrapper: frontWrapper,
            backWrapper: backWrapper,
            layout: layout,
            outputSize: outputSize,
            displayScale: displayScale,
            contentMode: contentMode,
            overlayInsets: overlayInsets
        )
    }

    /// Decodes raw front and back pixel buffers into `UIImage` instances on a background task.
    private nonisolated func decodeRawPhotosOffMainActor(
        frontWrapper: PixelBufferWrapper,
        backWrapper: PixelBufferWrapper,
        displayScale: CGFloat
    ) async throws -> (front: UIImage, back: UIImage) {
        try await Task.detached(priority: .userInitiated) {
            (
                front: try self.image(from: frontWrapper.buffer, displayScale: displayScale),
                back: try self.image(from: backWrapper.buffer, displayScale: displayScale)
            )
        }.value
    }

    /// Decodes raw front/back images and renders the composed image on a background task.
    private nonisolated func renderPhotoSetOffMainActor( // swiftlint:disable:this function_parameter_count
        frontWrapper: PixelBufferWrapper,
        backWrapper: PixelBufferWrapper,
        layout: DualCameraLayout,
        outputSize: CGSize,
        displayScale: CGFloat,
        contentMode: DualCameraContentMode,
        overlayInsets: EdgeInsets
    ) async throws -> DualCameraCapturedPhotoSet {
        try await Task.detached(priority: .userInitiated) {
            let resolvedLayout = self.layoutResolver.resolve(
                layout: layout,
                in: outputSize,
                overlayInsets: overlayInsets
            )
            let frontImage = try self.image(from: frontWrapper.buffer, displayScale: displayScale)
            let backImage = try self.image(from: backWrapper.buffer, displayScale: displayScale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = displayScale
            format.opaque = true

            let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
            let composedImage = renderer.image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: outputSize))

                for region in resolvedLayout.regionsInDrawingOrder {
                    let image = region.source == .front ? frontImage : backImage
                    self.draw(
                        image,
                        in: region.frame,
                        cornerRadius: self.cornerRadius(for: region, layout: layout),
                        contentMode: contentMode
                    )
                }
            }

            return DualCameraCapturedPhotoSet(
                composed: composedImage,
                frontRaw: frontImage,
                backRaw: backImage
            )
        }.value
    }

    /// Converts a `CVPixelBuffer` into a `UIImage` using the shared `CIContext`.
    private nonisolated func image(from buffer: CVPixelBuffer, displayScale: CGFloat) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return UIImage(cgImage: cgImage, scale: displayScale, orientation: .up)
    }

    /// Draws an image inside `targetRect` with optional rounded clipping and the specified content mode.
    private nonisolated func draw(
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

    /// Returns the corner radius for a resolved camera region (`10` for the PiP overlay, `0` otherwise).
    private nonisolated func cornerRadius(
        for region: DualCameraResolvedLayout.CameraRegion,
        layout: DualCameraLayout
    ) -> CGFloat {
        guard case .piP(let miniCamera, _) = layout, region.source == miniCamera else {
            return 0
        }
        return 10
    }

    /// Computes the drawing rectangle for `sourceSize` inside `targetRect` according to `contentMode`.
    private nonisolated func contentRect(
        for sourceSize: CGSize,
        in targetRect: CGRect,
        contentMode: DualCameraContentMode
    ) -> CGRect {
        DualCameraContentGeometry.contentRect(for: sourceSize, in: targetRect, contentMode: contentMode)
    }
}
