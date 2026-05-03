import CoreGraphics
import SwiftUI

/// Resolved display regions for a dual-camera layout.
public struct DualCameraResolvedLayout: Equatable, Sendable {
    public struct CameraRegion: Equatable, Sendable {
        public let source: DualCameraSource
        public let frame: CGRect
    }

    public let background: CameraRegion
    public let overlay: CameraRegion?

    public var regionsInDrawingOrder: [CameraRegion] {
        if let overlay {
            return [background, overlay]
        }
        return [background]
    }
}

/// Converts a semantic layout into concrete rectangles for display and capture.
public struct DualCameraLayoutResolver: Sendable {
    public init() {}

    public func resolve(
        layout: DualCameraLayout,
        in size: CGSize,
        overlayInsets: EdgeInsets = EdgeInsets()
    ) -> DualCameraResolvedLayout {
        let bounds = CGRect(origin: .zero, size: size)
        let overlayBounds = Self.inset(bounds, by: overlayInsets)

        switch layout {
        case .sideBySide:
            let halfWidth = size.width / 2
            return DualCameraResolvedLayout(
                background: .init(source: .back, frame: CGRect(x: 0, y: 0, width: halfWidth, height: size.height)),
                overlay: .init(source: .front, frame: CGRect(x: halfWidth, y: 0, width: halfWidth, height: size.height))
            )

        case .stackedVertical:
            let halfHeight = size.height / 2
            return DualCameraResolvedLayout(
                background: .init(source: .back, frame: CGRect(x: 0, y: 0, width: size.width, height: halfHeight)),
                overlay: .init(
                    source: .front,
                    frame: CGRect(x: 0, y: halfHeight, width: size.width, height: halfHeight)
                )
            )

        case .piP(let miniCamera, let position):
            let miniWidth = min(max(size.width * 0.38, 120), 180)
            let miniHeight = miniWidth * 16 / 9
            let padding: CGFloat = 16
            let miniOrigin = Self.origin(
                for: position,
                miniSize: CGSize(width: miniWidth, height: miniHeight),
                bounds: overlayBounds,
                padding: padding
            )

            return DualCameraResolvedLayout(
                background: .init(source: miniCamera == .front ? .back : .front, frame: bounds),
                overlay: .init(
                    source: miniCamera,
                    frame: CGRect(origin: miniOrigin, size: CGSize(width: miniWidth, height: miniHeight))
                )
            )
        }
    }

    private static func inset(_ bounds: CGRect, by insets: EdgeInsets) -> CGRect {
        let width = max(0, bounds.width - insets.leading - insets.trailing)
        let height = max(0, bounds.height - insets.top - insets.bottom)

        return CGRect(
            x: bounds.minX + insets.leading,
            y: bounds.minY + insets.top,
            width: width,
            height: height
        )
    }

    private static func origin(
        for position: DualCameraLayout.MiniCameraPosition,
        miniSize: CGSize,
        bounds: CGRect,
        padding: CGFloat
    ) -> CGPoint {
        switch position {
        case .topLeading:
            return CGPoint(x: bounds.minX + padding, y: bounds.minY + padding)
        case .topTrailing:
            return CGPoint(x: bounds.maxX - miniSize.width - padding, y: bounds.minY + padding)
        case .bottomLeading:
            return CGPoint(x: bounds.minX + padding, y: bounds.maxY - miniSize.height - padding)
        case .bottomTrailing:
            return CGPoint(x: bounds.maxX - miniSize.width - padding, y: bounds.maxY - miniSize.height - padding)
        }
    }
}
