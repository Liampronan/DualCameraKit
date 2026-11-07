@testable import DualCameraKit
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DualCameraPhotoCapturerTests: XCTestCase {
    func test_composedPhotoUsesResolvedLayoutRegions() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red)
        let back = try makePixelBuffer(color: .blue)

        let image = try await capturer.captureComposedPhoto(
            frontBuffer: front,
            backBuffer: back,
            layout: .sideBySide,
            outputSize: CGSize(width: 20, height: 10)
        )

        XCTAssertTrue(try image.isPixelNear(pixelX: 5, pixelY: 5, to: .blue))
        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 5, to: .red))
    }

    func test_rawPhotosReturnsBothCameraImages() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red)
        let back = try makePixelBuffer(color: .blue)

        let photos = try await capturer.captureRawPhotos(frontBuffer: front, backBuffer: back)

        XCTAssertTrue(try photos.front.isPixelNear(pixelX: 5, pixelY: 5, to: .red))
        XCTAssertTrue(try photos.back.isPixelNear(pixelX: 5, pixelY: 5, to: .blue))
    }

    func test_composedPhotoAspectFillCropsToFillRegionByDefault() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red, size: CGSize(width: 20, height: 10))
        let back = try makePixelBuffer(color: .blue, size: CGSize(width: 20, height: 10))

        let image = try await capturer.captureComposedPhoto(
            frontBuffer: front,
            backBuffer: back,
            layout: .sideBySide,
            outputSize: CGSize(width: 20, height: 10)
        )

        XCTAssertTrue(try image.isPixelNear(pixelX: 8, pixelY: 5, to: .blue))
        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 1, to: .red))
        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 8, to: .red))
    }

    func test_composedPhotoAspectFitLetterboxesRegion() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red, size: CGSize(width: 20, height: 10))
        let back = try makePixelBuffer(color: .blue, size: CGSize(width: 20, height: 10))

        let image = try await capturer.captureComposedPhoto(
            frontBuffer: front,
            backBuffer: back,
            layout: .sideBySide,
            outputSize: CGSize(width: 20, height: 10),
            displayScale: 1,
            contentMode: .aspectFit
        )

        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 1, to: .black))
        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 5, to: .red))
        XCTAssertTrue(try image.isPixelNear(pixelX: 15, pixelY: 8, to: .black))
    }

    func test_composedPhotoAppliesOverlayInsetsToPiP() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red, size: CGSize(width: 20, height: 20))
        let back = try makePixelBuffer(color: .blue, size: CGSize(width: 20, height: 20))
        let outputSize = CGSize(width: 400, height: 800)
        let insets = EdgeInsets(top: 100, leading: 0, bottom: 0, trailing: 0)

        let image = try await capturer.captureComposedPhoto(
            frontBuffer: front,
            backBuffer: back,
            layout: .piP(miniCamera: .front, miniCameraPosition: .topLeading),
            outputSize: outputSize,
            displayScale: 1,
            contentMode: .aspectFill,
            overlayInsets: insets
        )

        // Without top inset, the PiP top-leading corner would sit at y = 16 (red).
        // With top inset = 100, y = 30 is still background (.blue), and y = 150 is inside the PiP (.red).
        XCTAssertTrue(try image.isPixelNear(pixelX: 50, pixelY: 30, to: .blue))
        XCTAssertTrue(try image.isPixelNear(pixelX: 50, pixelY: 150, to: .red))
    }

    func test_capturePhotoSetReturnsComposedAndBothRawImages() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red, size: CGSize(width: 20, height: 10))
        let back = try makePixelBuffer(color: .blue, size: CGSize(width: 20, height: 10))

        let photoSet = try await capturer.capturePhotoSet(
            frontBuffer: front,
            backBuffer: back,
            layout: .sideBySide,
            outputSize: CGSize(width: 20, height: 10),
            displayScale: 2,
            contentMode: .aspectFill
        )

        XCTAssertEqual(photoSet.composed.scale, 2)
        XCTAssertEqual(photoSet.frontRaw.scale, 2)
        XCTAssertEqual(photoSet.backRaw.scale, 2)
        XCTAssertTrue(try photoSet.frontRaw.isPixelNear(pixelX: 5, pixelY: 5, to: .red))
        XCTAssertTrue(try photoSet.backRaw.isPixelNear(pixelX: 5, pixelY: 5, to: .blue))
        XCTAssertTrue(try photoSet.composed.isPixelNear(pixelX: 5, pixelY: 5, to: .blue))
        XCTAssertTrue(try photoSet.composed.isPixelNear(pixelX: 15, pixelY: 5, to: .red))
    }

    func test_capturePhotoSetThrowsUnknownDimensionsForZeroSize() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red)
        let back = try makePixelBuffer(color: .blue)

        do {
            _ = try await capturer.capturePhotoSet(
                frontBuffer: front,
                backBuffer: back,
                layout: .sideBySide,
                outputSize: .zero
            )
            XCTFail("Expected capturePhotoSet to throw")
        } catch {
            XCTAssertEqual(error as? DualCameraError, .captureFailure(.unknownDimensions))
        }
    }

    private func makePixelBuffer(color: UIColor) throws -> CVPixelBuffer {
        try makePixelBuffer(color: color, size: CGSize(width: 10, height: 10))
    }

    private func makePixelBuffer(color: UIColor, size: CGSize) throws -> CVPixelBuffer {
        guard let buffer = color.asImage(size).pixelBuffer() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return buffer
    }
}

private extension UIImage {
    func isPixelNear(pixelX: Int, pixelY: Int, to expectedColor: UIColor, tolerance: Int = 8) throws -> Bool {
        guard let cgImage else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }

        let scaledX = min(Int(CGFloat(pixelX) * scale), cgImage.width - 1)
        let scaledY = min(Int(CGFloat(pixelY) * scale), cgImage.height - 1)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        var pixel = [UInt8](repeating: 0, count: bytesPerPixel)

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DualCameraError.captureFailure(.contextCreationFailed)
        }

        context.translateBy(x: CGFloat(-scaledX), y: CGFloat(scaledY - cgImage.height + 1))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        expectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return abs(Int(pixel[0]) - Int(red * 255)) <= tolerance &&
            abs(Int(pixel[1]) - Int(green * 255)) <= tolerance &&
            abs(Int(pixel[2]) - Int(blue * 255)) <= tolerance
    }
}
