import CoreGraphics
import DualCameraKit
import Foundation
import UIKit

/// A custom image sticker that can be rendered over detected faces.
public struct EmojiOverlaySticker: @unchecked Sendable, Equatable, Identifiable {
    /// Identifier used for equality and texture-cache lookups.
    public let id: String
    /// Underlying bitmap image to composite over a detected face.
    public let cgImage: CGImage

    /// Creates a custom sticker overlay from a `CGImage`.
    // swiftlint:disable:next identifier_name
    public init(id: String = UUID().uuidString, cgImage: CGImage) {
        self.id = id
        self.cgImage = cgImage
    }

    /// Creates a custom sticker overlay from a `UIImage`, returning `nil` if it has no backing `CGImage`.
    // swiftlint:disable:next identifier_name
    public init?(id: String = UUID().uuidString, image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(id: id, cgImage: cgImage)
    }

    public static func == (lhs: EmojiOverlaySticker, rhs: EmojiOverlaySticker) -> Bool {
        lhs.id == rhs.id && lhs.cgImage === rhs.cgImage
    }
}

/// Strategy for assigning emoji or sticker overlays to detected faces.
public enum EmojiAssignmentStrategy: Sendable, Equatable {
    /// Renders the same emoji string over every detected face.
    case single(String)
    /// Deterministically assigns emojis from a non-empty palette to each tracked face ID.
    case palette([String])
    /// Renders a custom image sticker over every detected face.
    case sticker(EmojiOverlaySticker)

    /// Default emoji palette for multi-face or picker UIs.
    public static let defaultPalette: [String] = ["😎", "🦊", "🤖", "👻", "🐱", "🎃"]
}

/// Fallback behavior when no face is detected in a target camera frame.
public enum EmojiNoFaceFallback: Sendable, Equatable {
    /// Leaves the camera frame unmodified when no face is detected.
    case passThrough
    /// Applies a Gaussian blur across the frame when no face is detected (strict anonymity).
    case blurFrame(radius: CGFloat = 24)
}

/// Configuration controlling how `EmojiFaceFilterPlugin` detects and obscures faces.
public struct EmojiFaceFilterConfiguration: Sendable, Equatable {
    /// Whether the emoji face filter is active.
    public var isEnabled: Bool
    /// Camera sources that should have detected faces covered (defaults to `[.front]`).
    public var targetSources: Set<DualCameraSource>
    /// Strategy used to pick the emoji or sticker for each tracked face.
    public var assignment: EmojiAssignmentStrategy
    /// Scale multiplier applied to the Vision face bounding box (defaults to `1.45` to cover forehead and chin).
    public var scaleMultiplier: CGFloat
    /// Whether the rendered emoji tilts with the detected head roll angle.
    public var tracksHeadRoll: Bool
    /// Optional cap on how many faces to cover per camera (`nil` covers all detected faces, sorted largest-first).
    public var maxFaces: Int?
    /// Whether raw photos in `DualCameraCapturedPhotoSet` and `captureRawPhotos` also have the filter baked in.
    public var redactRawCaptures: Bool
    /// Behavior when a target camera frame contains no detected faces.
    public var noFaceFallback: EmojiNoFaceFallback
    /// Exponential moving average factor in `0.0...1.0` (`1.0` = unsmoothed raw detections, `0.65` = smooth tracking).
    public var smoothingFactor: CGFloat
    /// Duration (in seconds) to retain a tracked face overlay across brief detection dropouts.
    public var trackGracePeriod: TimeInterval

    /// Creates an emoji face filter configuration.
    public init(
        isEnabled: Bool = true,
        targetSources: Set<DualCameraSource> = [.front],
        assignment: EmojiAssignmentStrategy = .single("😎"),
        scaleMultiplier: CGFloat = 1.45,
        tracksHeadRoll: Bool = true,
        maxFaces: Int? = nil,
        redactRawCaptures: Bool = true,
        noFaceFallback: EmojiNoFaceFallback = .passThrough,
        smoothingFactor: CGFloat = 0.65,
        trackGracePeriod: TimeInterval = 0.15
    ) {
        self.isEnabled = isEnabled
        self.targetSources = targetSources
        self.assignment = assignment
        self.scaleMultiplier = max(0.1, scaleMultiplier)
        self.tracksHeadRoll = tracksHeadRoll
        self.maxFaces = maxFaces
        self.redactRawCaptures = redactRawCaptures
        self.noFaceFallback = noFaceFallback
        self.smoothingFactor = min(max(smoothingFactor, 0.05), 1.0)
        self.trackGracePeriod = max(0, trackGracePeriod)
    }
}
