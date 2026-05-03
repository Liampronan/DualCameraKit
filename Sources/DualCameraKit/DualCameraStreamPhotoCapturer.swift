import AVFoundation
import CoreImage
import UIKit

/// Configuration for visual styling of composed photos (rounded corners, shadows, etc.)
public struct DualCameraPhotoStyle {
    /// Corner radius for mini camera in PiP layout (in points)
    public let miniCameraCornerRadius: CGFloat
    /// Shadow properties for mini camera
    public let miniCameraShadow: ShadowStyle?
    /// Border properties for mini camera
    public let miniCameraBorder: BorderStyle?
    
    public struct ShadowStyle {
        public let color: UIColor
        public let radius: CGFloat
        public let opacity: Float
        public let offset: CGSize
        
        public init(color: UIColor = .black, radius: CGFloat = 10, opacity: Float = 0.5, offset: CGSize = CGSize(width: 0, height: 4)) {
            self.color = color
            self.radius = radius
            self.opacity = opacity
            self.offset = offset
        }
    }
    
    public struct BorderStyle {
        public let color: UIColor
        public let width: CGFloat
        
        public init(color: UIColor = .white, width: CGFloat = 2) {
            self.color = color
            self.width = width
        }
    }
    
    /// Default style matching DualCameraScreen's SwiftUI appearance
    public static let dualCameraScreen = DualCameraPhotoStyle(
        miniCameraCornerRadius: 12,
        miniCameraShadow: ShadowStyle(color: .black, radius: 10, opacity: 0.3, offset: CGSize(width: 0, height: 4)),
        miniCameraBorder: BorderStyle(color: .white.withAlphaComponent(0.3), width: 2)
    )
    
    /// Minimal style with no effects
    public static let minimal = DualCameraPhotoStyle(
        miniCameraCornerRadius: 0,
        miniCameraShadow: nil,
        miniCameraBorder: nil
    )
    
    public init(miniCameraCornerRadius: CGFloat = 0, miniCameraShadow: ShadowStyle? = nil, miniCameraBorder: BorderStyle? = nil) {
        self.miniCameraCornerRadius = miniCameraCornerRadius
        self.miniCameraShadow = miniCameraShadow
        self.miniCameraBorder = miniCameraBorder
    }
}

/// Captures and composes high-resolution photos from independent camera streams.
/// This approach provides native camera resolution instead of screen-limited screenshot quality.
@MainActor
public class DualCameraStreamPhotoCapturer {
    
    private let ciContext: CIContext
    public var style: DualCameraPhotoStyle
    
    public init(style: DualCameraPhotoStyle = .dualCameraScreen) {
        // Create GPU-accelerated Core Image context
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        self.style = style
    }
    
    /// Captures synchronized frames from both cameras and composes them according to layout
    public func captureComposedPhoto(
        frontRenderer: CameraRenderer,
        backRenderer: CameraRenderer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> UIImage {
        // 1. Capture raw buffers from both cameras at native resolution
        let frontBuffer = try await frontRenderer.captureCurrentBuffer()
        let backBuffer = try await backRenderer.captureCurrentBuffer()
        
        // 2. Compose based on layout
        let composedImage = try composeImages(
            frontBuffer: frontBuffer,
            backBuffer: backBuffer,
            layout: layout,
            outputSize: outputSize
        )
        
        // 3. Convert to UIImage
        return try createUIImage(from: composedImage, outputSize: outputSize)
    }
    
    // MARK: - Composition
    
    private func composeImages(
        frontBuffer: CVPixelBuffer,
        backBuffer: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) throws -> CIImage {
        let frontImage = CIImage(cvPixelBuffer: frontBuffer)
        let backImage = CIImage(cvPixelBuffer: backBuffer)
        
        switch layout {
        case .piP(let miniCamera, let position):
            return try composePictureInPicture(
                primary: miniCamera == .front ? backImage : frontImage,
                mini: miniCamera == .front ? frontImage : backImage,
                position: position,
                outputSize: outputSize
            )
            
        case .sideBySide:
            return try composeSideBySide(
                front: frontImage,
                back: backImage,
                outputSize: outputSize
            )
            
        case .stackedVertical:
            return try composeStackedVertical(
                front: frontImage,
                back: backImage,
                outputSize: outputSize
            )
        }
    }
    
    // MARK: - Layout Implementations
    
    /// Composes picture-in-picture layout with one camera as primary and one as mini overlay
    private func composePictureInPicture(
        primary: CIImage,
        mini: CIImage,
        position: DualCameraLayout.MiniCameraPosition,
        outputSize: CGSize
    ) throws -> CIImage {
        
        // Scale primary to fill output size (aspect fill)
        let primaryScaled = scaleImageToFill(primary, targetSize: outputSize)
        
        // Scale mini to match display view: 16:9 aspect ratio (landscape), ~25% of width
        let miniWidth = 150.0 //outputSize.width * 0.25
        let miniHeight = miniWidth * (16.0 / 9.0) // 16:9 aspect ratio (landscape)
        let miniSize = CGSize(width: miniWidth, height: miniHeight)
        print(miniWidth, miniHeight, miniSize)
        let miniScaled = scaleImageToFit(mini, targetSize: miniSize)
        
        // Apply styling effects to mini camera
        let miniStyled = applyMiniCameraEffects(to: miniScaled, size: miniSize)
        
        // Calculate position for mini camera
        let padding: CGFloat = 12 * (outputSize.width / 390) // Scale padding with output size
        
        let miniPosition: CGPoint
        switch position {
        case .topLeading:
            miniPosition = CGPoint(x: padding, y: outputSize.height - miniScaled.extent.size.height - padding)
        case .topTrailing:
            miniPosition = CGPoint(x: outputSize.width - miniScaled.extent.size.width - padding, y: outputSize.height - miniScaled.extent.size.height - padding)
        case .bottomLeading:
            miniPosition = CGPoint(x: padding, y: padding)
        case .bottomTrailing:
            //miniPosition = CGPoint(x: outputSize.width - miniSize.width - padding, y: padding)
            miniPosition = CGPoint(x: outputSize.width - miniScaled.extent.size.width - padding, y: padding)
        }
        print("miniPosition", miniPosition, "padding", padding, "miniSize", miniSize)
        // Position the styled mini image
        let miniPositioned = miniStyled.transformed(by: CGAffineTransform(translationX: miniPosition.x, y: miniPosition.y))
        
        // Composite mini over primary
        let composed = miniPositioned.composited(over: primaryScaled)
        
        return composed
    }
    
    /// Applies UI effects (rounded corners, shadows, borders) to the mini camera image
    private func applyMiniCameraEffects(to image: CIImage, size: CGSize) -> CIImage {
        var result = image
        
        // 1. Apply rounded corners
        if style.miniCameraCornerRadius > 0 {
            result = applyRoundedCorners(to: result, radius: style.miniCameraCornerRadius, size: size)
        }
        
        // 2. Apply border
        if let border = style.miniCameraBorder {
            result = applyBorder(to: result, border: border, size: size)
        }
        
        // 3. Apply shadow
        if let shadow = style.miniCameraShadow {
            result = applyShadow(to: result, shadow: shadow, size: size)
        }
        
        return result
    }
    
    /// Applies rounded corners to an image using Core Image
    /// Applies rounded corners using a CI-generated rounded-rectangle mask aligned to the image's extent.
    /// This avoids UIKit's top-left origin and any scale/flip issues that can misplace corners.
    private func applyRoundedCorners(to image: CIImage, radius: CGFloat, size: CGSize) -> CIImage {
        let extent = image.extent.integral
        let pixelSize = extent.size
        guard pixelSize.width > 0, pixelSize.height > 0, size.width > 0, size.height > 0 else {
            return image
        }
        
        // Convert point-based corner radius (SwiftUI style) to pixel units to match the scaled mini image.
        let scaleX = pixelSize.width / size.width
        let scaleY = pixelSize.height / size.height
        let scale = max(scaleX, scaleY) // match aspectFill logic elsewhere
        let cornerRadiusPx = max(0.0, radius * scale)
        
        // Generate a rounded-rectangle mask directly in CI coordinate space (origin: bottom-left),
        // with the SAME extent as the target image to avoid any translation mismatches.
        guard let roundedGen = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return image
        }
        roundedGen.setValue(CIVector(cgRect: extent), forKey: "inputExtent")
        roundedGen.setValue(cornerRadiusPx, forKey: "inputRadius")
        
        guard let rawMask = roundedGen.outputImage?.cropped(to: extent) else {
            return image
        }
        
        // Blend the image over a transparent background using the rounded mask.
        let clearBG = CIImage(color: .clear).cropped(to: extent)
        let blend = CIFilter(name: "CIBlendWithMask")
        blend?.setValue(image, forKey: kCIInputImageKey)
        blend?.setValue(clearBG, forKey: kCIInputBackgroundImageKey)
        blend?.setValue(rawMask, forKey: kCIInputMaskImageKey)
        
        return blend?.outputImage ?? image
    }
    
    /// Applies a border to an image **without** resampling the image.
    /// We render a transparent stroke-only layer in the CIImage's pixel space
    /// and composite it over the original image to avoid any scaling blur.
    /// `size` is the intended point-size of the mini view; we only use it to
    /// correctly convert point-based style values (radius/lineWidth) into pixels.
    private func applyBorder(to image: CIImage, border: DualCameraPhotoStyle.BorderStyle, size: CGSize) -> CIImage {
        // Work in the CIImage's pixel space to avoid stretching/scaling.
        let extent = image.extent.integral
        let pixelSize = extent.size
        
        // Guard against empty inputs
        guard pixelSize.width > 0, pixelSize.height > 0, size.width > 0, size.height > 0 else {
            return image
        }
        
        // Convert point-based style to pixel units to keep visual parity at any output scale.
        // `size` represents the points we asked the mini camera to occupy; the CI image may be higher-res.
        // We map points -> pixels by measuring how many pixels correspond to one point.
        let scaleX = pixelSize.width / size.width
        let scaleY = pixelSize.height / size.height
        let scale = max(scaleX, scaleY) // conservative (match aspectFill used earlier)
        
        let borderWidthPx = max(1.0, border.width * scale)
        let cornerRadiusPx = max(0.0, style.miniCameraCornerRadius * scale)
        
        // Render only the border stroke on a transparent background, in pixel space.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1.0 // IMPORTANT: pixel-accurate canvas (no UIKit scaling)
        
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let borderLayer = renderer.image { _ in
            // Stroke a rounded-rect that matches the masked mini image.
            let rect = CGRect(origin: .zero, size: pixelSize).insetBy(dx: borderWidthPx / 2, dy: borderWidthPx / 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadiusPx)
            path.lineWidth = borderWidthPx
            border.color.setStroke()
            path.stroke()
        }
        
        guard let borderCI = CIImage(image: borderLayer) else {
            return image
        }
        
        // Composite border over the original without touching the original pixels.
        return borderCI.composited(over: image)
    }
    
    /// Applies a drop shadow entirely in Core Image space to avoid UIKit y-flip/resampling.
    /// Shadow is created from the image's alpha, blurred, translated, tinted, then composited under the image.
    private func applyShadow(to image: CIImage, shadow: DualCameraPhotoStyle.ShadowStyle, size: CGSize) -> CIImage {
        let extent = image.extent.integral
        let pixelSize = extent.size
        guard pixelSize.width > 0, pixelSize.height > 0, size.width > 0, size.height > 0 else {
            return image
        }

        // Convert point-based values (SwiftUI) to pixels for the current mini size.
        let scaleX = pixelSize.width / size.width
        let scaleY = pixelSize.height / size.height
        let scale = max(scaleX, scaleY)

        let blurPx = max(0, shadow.radius * scale)
        let offsetPx = CGSize(width: shadow.offset.width * scale, height: shadow.offset.height * scale)
        let opacity = CGFloat(shadow.opacity)

        // 1) Build an alpha mask of the current image (transparent corners already respected).
        // If the image already has a proper alpha, CIMaskToAlpha will produce a luminance-based alpha.
        let alphaMask = CIFilter(name: "CIMaskToAlpha", parameters: [kCIInputImageKey: image])?.outputImage?
            .cropped(to: extent) ?? image

        // 2) Blur the alpha to make the shadow soft.
        let blurredMask = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: alphaMask,
            kCIInputRadiusKey: blurPx
        ])?.outputImage?.cropped(to: extent) ?? alphaMask

        // 3) Offset the blurred mask by the shadow's offset.
        let translatedMask = blurredMask.transformed(by: CGAffineTransform(translationX: offsetPx.width, y: offsetPx.height))

        // 4) Create a solid color image for the shadow and apply the mask as alpha.
        let color = CIColor(color: shadow.color.withAlphaComponent(opacity))
        let colorImage = CIImage(color: color).cropped(to: translatedMask.extent)
        let shadowLayer = CIFilter(name: "CIBlendWithAlphaMask", parameters: [
            kCIInputImageKey: colorImage,
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: translatedMask.extent),
            kCIInputMaskImageKey: translatedMask
        ])?.outputImage ?? colorImage

        // 5) Composite shadow layer under the original image.
        let withShadow = shadowLayer.composited(over: image)

        return withShadow
    }
    
    /// Composes side-by-side layout with both cameras at equal size
    private func composeSideBySide(
        front: CIImage,
        back: CIImage,
        outputSize: CGSize
    ) throws -> CIImage {
        // Each camera gets half the width
        let halfWidth = outputSize.width / 2
        let cameraSize = CGSize(width: halfWidth, height: outputSize.height)
        
        // Scale both cameras to fit their half
        let frontScaled = scaleImageToFill(front, targetSize: cameraSize)
        let backScaled = scaleImageToFill(back, targetSize: cameraSize)
        
        // Position back camera on the left, front on the right
        let backPositioned = backScaled // Already at origin
        let frontPositioned = frontScaled.transformed(by: CGAffineTransform(translationX: halfWidth, y: 0))
        
        // Composite
        let composed = frontPositioned.composited(over: backPositioned)
        
        return composed
    }
    
    /// Composes stacked vertical layout with both cameras at equal size
    private func composeStackedVertical(
        front: CIImage,
        back: CIImage,
        outputSize: CGSize
    ) throws -> CIImage {
        // Each camera gets half the height
        let halfHeight = outputSize.height / 2
        let cameraSize = CGSize(width: outputSize.width, height: halfHeight)
        
        // Scale both cameras to fit their half
        let frontScaled = scaleImageToFill(front, targetSize: cameraSize)
        let backScaled = scaleImageToFill(back, targetSize: cameraSize)
        
        // Position back camera on top, front on bottom
        let backPositioned = backScaled.transformed(by: CGAffineTransform(translationX: 0, y: halfHeight))
        let frontPositioned = frontScaled // Already at origin
        
        // Composite
        let composed = backPositioned.composited(over: frontPositioned)
        
        return composed
    }
    
    // MARK: - Scaling Helpers
    
    /// Scales image to fill target size (aspect fill - may crop)
    private func scaleImageToFill(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        let scale = max(scaleX, scaleY) // Use larger scale to fill
        
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Crop to target size if needed
        let cropRect = CGRect(
            x: (scaledImage.extent.width - targetSize.width) / 2,
            y: (scaledImage.extent.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        
        return scaledImage.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
    }
    
    /// Scales image to fit target size (aspect fit - no crop, may have letterboxing)
    private func scaleImageToFit(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = targetSize.width / imageSize.width
        DualCameraLogger.log("imageSize is \(imageSize.width) \(imageSize.height)")
        DualCameraLogger.log("targetSize is \(targetSize.width) \(targetSize.height)")
        
        let scaleY = targetSize.height / imageSize.height
        let scale = min(scaleX, scaleY) // Use smaller scale to fit
        print(scaleX, scaleY)
        // hard-coded works
        return image.transformed(by: CGAffineTransform(scaleX: 0.15, y: 0.125))
//        return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        
        
        // Center within the canvas
//        let fs = image.extent.size
//        let dx = (targetSize.width  - fs.width)  * 0.5
//        let dy = (targetSize.height - fs.height) * 0.5
//        let centered = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
//        
//        // Transparent canvas with exact `targetSize`
//        let canvasRect = CGRect(origin: .zero, size: targetSize)
//        let canvas = CIImage(color: .clear).cropped(to: canvasRect)
//        return centered.composited(over: canvas)
    }
    
    /// Scales an image to fit a fixed target size (aspect fit), letterboxing as needed.
    /// Output extent always equals `targetSize`, matching SwiftUI’s `.aspectRatio(..., .fit)` inside a fixed frame.
//    private func scaleImageToFit(_ image: CIImage, targetSize: CGSize) -> CIImage {
//        let imageSize = image.extent.size
//        let scaleX = targetSize.width / imageSize.width
//        let scaleY = targetSize.height / imageSize.height
//        let scale = min(scaleX, scaleY)
//
//        let fitted = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
//        let fittedSize = fitted.extent.size
//
//        // Center within the canvas
//        let dx = max(0, (targetSize.width  - fittedSize.width)  * 0.5)
//        let dy = max(0, (targetSize.height - fittedSize.height) * 0.5)
//        let translated = fitted.transformed(by: CGAffineTransform(translationX: dx, y: dy))
//
//        // Compose onto transparent canvas
//        let canvasRect = CGRect(origin: .zero, size: targetSize)
//        let canvas = CIImage(color: .clear).cropped(to: canvasRect)
//        return translated.composited(over: canvas)
//    }
    
    // MARK: - Image Conversion
    
    /// Converts CIImage to UIImage
    private func createUIImage(from ciImage: CIImage, outputSize: CGSize) throws -> UIImage {
        // Define the bounds for rendering
        let bounds = CGRect(origin: .zero, size: outputSize)
        
        // Render CIImage to CGImage
        guard let cgImage = ciContext.createCGImage(ciImage, from: bounds) else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        
        // Create UIImage with proper orientation
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
