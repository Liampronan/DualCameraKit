import UIKit

/// A deterministic, alignment-friendly fixture image for mock camera streams.
///
/// Each frame has a grid, a labelled marker flush in every corner (TL, TR, BL, BR), a centre crosshair,
/// the camera name (FRONT or BACK) and the frame's pixel size. Crops, letterboxing, flips and offsets are
/// visible at a glance: a missing or clipped corner marker means the frame was cropped on that side, and a
/// crosshair that is not centred in its region means the frame was offset.
///
/// Corner marker and background colours are public so tests can sample captured images for them.
public enum DualCameraTestPattern {
    /// Portrait 3:4, the aspect ratio of the 4:3 formats iPhone cameras typically default to, after the
    /// capture connection rotates frames to portrait.
    public static let portrait3x4FrameSize = CGSize(width: 1080, height: 1440)

    /// Portrait 9:16, the aspect ratio of 16:9 (1080p and 4K) video formats after rotation to portrait.
    public static let portrait9x16FrameSize = CGSize(width: 1080, height: 1920)

    /// The frame size test-pattern mocks use unless told otherwise. See the README section
    /// "Simulator and test fixtures" for why this is 3:4.
    public static let defaultFrameSize = portrait3x4FrameSize

    /// A corner of the frame and the marker drawn in it.
    public enum Corner: CaseIterable, Sendable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        /// The text drawn on the marker.
        public var label: String {
            switch self {
            case .topLeft: "TL"
            case .topRight: "TR"
            case .bottomLeft: "BL"
            case .bottomRight: "BR"
            }
        }

        /// The marker's fill colour. Fully saturated so it survives colour conversion and is easy to sample.
        public var color: UIColor {
            switch self {
            case .topLeft: UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            case .topRight: UIColor(red: 0, green: 1, blue: 0, alpha: 1)
            case .bottomLeft: UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            case .bottomRight: UIColor(red: 1, green: 1, blue: 0, alpha: 1)
            }
        }
    }

    /// The flat background colour behind the grid, different per camera.
    public static func backgroundColor(for source: DualCameraSource) -> UIColor {
        switch source {
        case .front: UIColor(red: 0, green: 0.36, blue: 0.42, alpha: 1)
        case .back: UIColor(red: 0.34, green: 0.12, blue: 0.4, alpha: 1)
        }
    }

    /// The side length, in pixels, of each square corner marker in a frame of `size`.
    public static func markerSideLength(for size: CGSize) -> CGFloat {
        (min(size.width, size.height) * 0.18).rounded()
    }

    /// The rectangle, in pixels with the origin at the top left, of `corner`'s marker in a frame of `size`.
    public static func markerRect(for corner: Corner, in size: CGSize) -> CGRect {
        let side = markerSideLength(for: size)
        let originX: CGFloat
        let originY: CGFloat
        switch corner {
        case .topLeft:
            originX = 0
            originY = 0
        case .topRight:
            originX = size.width - side
            originY = 0
        case .bottomLeft:
            originX = 0
            originY = size.height - side
        case .bottomRight:
            originX = size.width - side
            originY = size.height - side
        }
        return CGRect(x: originX, y: originY, width: side, height: side)
    }

    /// Renders the pattern for `source` at exactly `size` pixels (scale 1, orientation up).
    @MainActor
    public static func image(for source: DualCameraSource, size: CGSize = defaultFrameSize) -> UIImage {
        let pixelSize = CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Plain 8-bit sRGB, so pixel values match the public colours on wide-colour devices too.
        format.preferredRange = .standard

        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let bounds = CGRect(origin: .zero, size: pixelSize)
            backgroundColor(for: source).setFill()
            context.fill(bounds)

            drawGrid(in: bounds, context: context)
            drawCrosshair(in: bounds, context: context)
            drawTitle(for: source, in: bounds)
            for corner in Corner.allCases {
                drawMarker(corner, in: bounds)
            }
        }
    }

    @MainActor
    private static func drawGrid(in bounds: CGRect, context: CGContext) {
        // Square cells: eight columns across, as many rows as fit.
        let step = bounds.width / 8
        let lineWidth = max(1, (bounds.width / 360).rounded())
        context.saveGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(lineWidth)
        for column in stride(from: step, to: bounds.maxX - 0.5, by: step) {
            context.move(to: CGPoint(x: column, y: 0))
            context.addLine(to: CGPoint(x: column, y: bounds.maxY))
        }
        for row in stride(from: step, to: bounds.maxY - 0.5, by: step) {
            context.move(to: CGPoint(x: 0, y: row))
            context.addLine(to: CGPoint(x: bounds.maxX, y: row))
        }
        context.strokePath()

        // Frame edge, so a crop shows as a missing border.
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(lineWidth * 4)
        context.stroke(bounds.insetBy(dx: lineWidth * 2, dy: lineWidth * 2))
        context.restoreGState()
    }

    @MainActor
    private static func drawCrosshair(in bounds: CGRect, context: CGContext) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let armLength = min(bounds.width, bounds.height) * 0.12
        let lineWidth = max(2, (bounds.width / 180).rounded())
        context.saveGState()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(lineWidth)
        context.move(to: CGPoint(x: center.x - armLength, y: center.y))
        context.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
        context.move(to: CGPoint(x: center.x, y: center.y - armLength))
        context.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
        context.strokePath()
        let radius = armLength * 0.6
        context.strokeEllipse(
            in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        )
        context.restoreGState()
    }

    @MainActor
    private static func drawTitle(for source: DualCameraSource, in bounds: CGRect) {
        let title = source == .front ? "FRONT" : "BACK"
        let fontSize = min(bounds.width, bounds.height) * 0.12
        let subtitleSize = fontSize * 0.4
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: subtitleSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let subtitle = "\(Int(bounds.width))×\(Int(bounds.height))"

        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let subtitleTextSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
        let titleOrigin = CGPoint(x: bounds.midX - titleSize.width / 2, y: bounds.height * 0.24)
        (title as NSString).draw(at: titleOrigin, withAttributes: titleAttributes)
        (subtitle as NSString).draw(
            at: CGPoint(x: bounds.midX - subtitleTextSize.width / 2, y: titleOrigin.y + titleSize.height),
            withAttributes: subtitleAttributes
        )
    }

    @MainActor
    private static func drawMarker(_ corner: Corner, in bounds: CGRect) {
        let rect = markerRect(for: corner, in: bounds.size)
        corner.color.setFill()
        UIRectFill(rect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: rect.height * 0.36, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let label = corner.label as NSString
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.midY - labelSize.height / 2),
            withAttributes: attributes
        )
    }
}
