import CoreGraphics
import simd

@_spi(Testing) public enum DualCameraContentGeometry: Sendable {
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

    public static func rendererScale(
        for sourceSize: CGSize,
        in targetSize: CGSize,
        contentMode: DualCameraContentMode
    ) -> SIMD2<Float> {
        guard targetSize.width > 0, targetSize.height > 0 else {
            return SIMD2<Float>(1, 1)
        }

        let contentRect = contentRect(
            for: sourceSize,
            in: CGRect(origin: .zero, size: targetSize),
            contentMode: contentMode
        )

        return SIMD2<Float>(
            Float(contentRect.width / targetSize.width),
            Float(contentRect.height / targetSize.height)
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
