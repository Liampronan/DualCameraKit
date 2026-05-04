import CoreGraphics
import simd

/// Shared geometry for fitting camera frames into preview and capture regions.
@_spi(Testing) public enum DualCameraContentGeometry: Sendable {
    /// Returns the rectangle used to draw a source image inside a target region.
    public static func contentRect(
        for sourceSize: CGSize,
        in targetRect: CGRect,
        contentMode: DualCameraContentMode
    ) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetRect.width > 0,
              targetRect.height > 0 else {
            return targetRect
        }

        let widthRatio = targetRect.width / sourceSize.width
        let heightRatio = targetRect.height / sourceSize.height
        let scale = scaleFactor(widthRatio: widthRatio, heightRatio: heightRatio, contentMode: contentMode)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Returns the Metal quad scale that matches `contentRect` for the same source and target sizes.
    public static func rendererScale(
        for sourceSize: CGSize,
        in targetSize: CGSize,
        contentMode: DualCameraContentMode
    ) -> SIMD2<Float> {
        guard targetSize.width > 0,
              targetSize.height > 0,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return SIMD2<Float>(1, 1)
        }

        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scale = scaleFactor(widthRatio: widthRatio, heightRatio: heightRatio, contentMode: contentMode)

        return SIMD2<Float>(
            Float(scale / widthRatio),
            Float(scale / heightRatio)
        )
    }

    private static func scaleFactor(
        widthRatio: CGFloat,
        heightRatio: CGFloat,
        contentMode: DualCameraContentMode
    ) -> CGFloat {
        switch contentMode {
        case .aspectFill:
            max(widthRatio, heightRatio)
        case .aspectFit:
            min(widthRatio, heightRatio)
        }
    }
}
