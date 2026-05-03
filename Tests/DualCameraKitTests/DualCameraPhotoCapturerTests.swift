@testable import DualCameraKit
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

        XCTAssertTrue(try image.isPixelNear(x: 5, y: 5, to: .blue))
        XCTAssertTrue(try image.isPixelNear(x: 15, y: 5, to: .red))
    }

    func test_rawPhotosReturnsBothCameraImages() async throws {
        let capturer = DualCameraPhotoCapturer()
        let front = try makePixelBuffer(color: .red)
        let back = try makePixelBuffer(color: .blue)

        let photos = try await capturer.captureRawPhotos(frontBuffer: front, backBuffer: back)

        XCTAssertTrue(try photos.front.isPixelNear(x: 5, y: 5, to: .red))
        XCTAssertTrue(try photos.back.isPixelNear(x: 5, y: 5, to: .blue))
    }

    private func makePixelBuffer(color: UIColor) throws -> CVPixelBuffer {
        guard let buffer = color.asImage(CGSize(width: 10, height: 10)).pixelBuffer() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return buffer
    }
}

private extension UIImage {
    func isPixelNear(x: Int, y: Int, to expectedColor: UIColor, tolerance: Int = 8) throws -> Bool {
        guard let cgImage else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }

        let scaledX = min(Int(CGFloat(x) * scale), cgImage.width - 1)
        let scaledY = min(Int(CGFloat(y) * scale), cgImage.height - 1)
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

