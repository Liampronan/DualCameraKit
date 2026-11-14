import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Metal
import os
import UIKit

/// Composites tracked emoji or sticker overlays onto camera pixel buffers using Core Image and Metal.
final class EmojiBufferCompositor: Sendable {
    private static let emojiTextureDimension: CGFloat = 512

    private struct PoolState: @unchecked Sendable {
        var width: Int = 0
        var height: Int = 0
        var pool: CVPixelBufferPool?
    }

    private struct CachedSticker: Sendable {
        let cgImageID: ObjectIdentifier
        let image: CIImage
    }

    private let ciContext: CIContext
    private let emojiCache = OSAllocatedUnfairLock(initialState: [String: CIImage]())
    private let stickerCache = OSAllocatedUnfairLock(initialState: [String: CachedSticker]())
    private let poolState = OSAllocatedUnfairLock(initialState: PoolState())

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext(options: [
                .cacheIntermediates: false
            ])
        }
    }

    /// Renders `overlays` (or `configuration.noFaceFallback` when `overlays` is empty) onto a pooled `CVPixelBuffer`.
    func composite(
        overlays: [TrackedFaceOverlay],
        onto inputBuffer: CVPixelBuffer,
        configuration: EmojiFaceFilterConfiguration
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(inputBuffer)
        let height = CVPixelBufferGetHeight(inputBuffer)
        guard width > 0, height > 0 else { return nil }

        let baseImage = CIImage(cvPixelBuffer: inputBuffer)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)

        let compositedImage: CIImage
        if overlays.isEmpty {
            switch configuration.noFaceFallback {
            case .passThrough:
                return inputBuffer
            case .blurFrame(let radius):
                compositedImage = Self.blurredImage(from: baseImage, extent: extent, radius: radius)
            }
        } else {
            var currentImage = baseImage
            for overlay in overlays {
                guard let stickerImage = overlayCIImage(
                    for: overlay,
                    assignment: configuration.assignment
                ) else {
                    return nil
                }

                let transformedSticker = Self.transformedSticker(
                    stickerImage,
                    for: overlay,
                    in: extent,
                    scaleMultiplier: configuration.scaleMultiplier
                )
                currentImage = transformedSticker.composited(over: currentImage)
            }
            compositedImage = currentImage.cropped(to: extent)
        }

        guard let outputBuffer = makeOutputPixelBuffer(width: width, height: height) else {
            return nil
        }

        ciContext.render(
            compositedImage,
            to: outputBuffer,
            bounds: extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return outputBuffer
    }

    // MARK: - Sticker Lookup & Rasterization

    private func overlayCIImage(
        for overlay: TrackedFaceOverlay,
        assignment: EmojiAssignmentStrategy
    ) -> CIImage? {
        switch assignment {
        case .single(let emoji):
            return cachedEmojiCIImage(for: emoji)
        case .palette(let emojis):
            let palette = emojis.isEmpty ? EmojiAssignmentStrategy.defaultPalette : emojis
            let rawIndex = abs(overlay.trackID &+ overlay.paletteOffset)
            let emoji = palette[rawIndex % palette.count]
            return cachedEmojiCIImage(for: emoji)
        case .sticker(let sticker):
            let cgImageID = ObjectIdentifier(sticker.cgImage)
            if let cached = stickerCache.withLock({ $0[sticker.id] }),
               cached.cgImageID == cgImageID {
                return cached.image
            }
            let image = CIImage(cgImage: sticker.cgImage)
            stickerCache.withLock {
                $0[sticker.id] = CachedSticker(cgImageID: cgImageID, image: image)
            }
            return image
        }
    }

    private func cachedEmojiCIImage(for emoji: String) -> CIImage? {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmoji = trimmed.isEmpty ? "😎" : trimmed

        if let cached = emojiCache.withLock({ $0[resolvedEmoji] }) {
            return cached
        }

        guard let rendered = Self.rasterizeEmoji(resolvedEmoji) else {
            return nil
        }

        emojiCache.withLock {
            $0[resolvedEmoji] = rendered
        }
        return rendered
    }

    private static func rasterizeEmoji(_ emoji: String) -> CIImage? {
        let dimension = emojiTextureDimension
        let size = CGSize(width: dimension, height: dimension)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let fontSize = dimension * 0.82
            let font = UIFont.systemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributed = NSAttributedString(string: emoji, attributes: attributes)
            let textSize = attributed.size()
            let drawOrigin = CGPoint(
                x: (dimension - textSize.width) / 2,
                y: (dimension - textSize.height) / 2
            )
            attributed.draw(at: drawOrigin)
        }

        guard let cgImage = image.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Geometry & Filters

    private static func transformedSticker(
        _ sticker: CIImage,
        for overlay: TrackedFaceOverlay,
        in extent: CGRect,
        scaleMultiplier: CGFloat
    ) -> CIImage {
        let stickerExtent = sticker.extent
        guard stickerExtent.width > 0, stickerExtent.height > 0 else {
            return sticker
        }

        let faceWidth = overlay.normalizedBoundingBox.width * extent.width
        let faceHeight = overlay.normalizedBoundingBox.height * extent.height
        let targetDiameter = max(faceWidth, faceHeight) * scaleMultiplier
        let scaleX = targetDiameter / stickerExtent.width
        let scaleY = targetDiameter / stickerExtent.height

        let faceCenterX = overlay.normalizedBoundingBox.midX * extent.width
        let faceCenterY = overlay.normalizedBoundingBox.midY * extent.height

        // Center sticker at origin, scale, rotate by head roll, then translate to face center.
        var transform = CGAffineTransform(
            translationX: -stickerExtent.midX,
            y: -stickerExtent.midY
        )
        transform = transform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
        if overlay.rollAngleRadians != 0 {
            transform = transform.concatenating(CGAffineTransform(rotationAngle: overlay.rollAngleRadians))
        }
        transform = transform.concatenating(CGAffineTransform(translationX: faceCenterX, y: faceCenterY))

        return sticker.transformed(by: transform)
    }

    private static func blurredImage(from baseImage: CIImage, extent: CGRect, radius: CGFloat) -> CIImage {
        let clampedRadius = Float(max(1, radius))
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = baseImage.clampedToExtent()
        filter.radius = clampedRadius
        return (filter.outputImage ?? baseImage).cropped(to: extent)
    }

    // MARK: - Pixel Buffer Pool

    private func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        poolState.withLockUnchecked { state in
            let pool: CVPixelBufferPool?
            if state.width == width, state.height == height, let existingPool = state.pool {
                pool = existingPool
            } else {
                let poolAttributes: [String: Any] = [
                    kCVPixelBufferPoolMinimumBufferCountKey as String: 3
                ]
                let bufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]

                var newPool: CVPixelBufferPool?
                let status = CVPixelBufferPoolCreate(
                    kCFAllocatorDefault,
                    poolAttributes as CFDictionary,
                    bufferAttributes as CFDictionary,
                    &newPool
                )
                guard status == kCVReturnSuccess else {
                    return nil
                }

                state.width = width
                state.height = height
                state.pool = newPool
                pool = newPool
            }

            guard let pool else { return nil }
            var outputBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
            guard status == kCVReturnSuccess else { return nil }
            return outputBuffer
        }
    }
}
