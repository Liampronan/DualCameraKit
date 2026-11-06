import CoreVideo
import UIKit

struct RGBPixel: Equatable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(
            red: Int((red * 255).rounded()),
            green: Int((green * 255).rounded()),
            blue: Int((blue * 255).rounded())
        )
    }

    func isNear(pixel other: RGBPixel, tolerance: Int = 10) -> Bool {
        abs(red - other.red) <= tolerance &&
            abs(green - other.green) <= tolerance &&
            abs(blue - other.blue) <= tolerance
    }

    func isNear(_ color: UIColor, tolerance: Int = 10) -> Bool {
        isNear(pixel: RGBPixel(color), tolerance: tolerance)
    }

    var description: String { "rgb(\(red), \(green), \(blue))" }
}

enum PixelSamplingError: Error {
    case missingCGImage
    case contextCreationFailed
    case outOfBounds
}

extension CGImage {
    /// Reads the pixel at (`x`, `y`) in pixels, with the origin at the top left.
    func rgbPixel(x: Int, y: Int) throws -> RGBPixel {
        guard x >= 0, y >= 0, x < width, y < height else {
            throw PixelSamplingError.outOfBounds
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PixelSamplingError.contextCreationFailed
        }

        context.translateBy(x: CGFloat(-x), y: CGFloat(y - height + 1))
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBPixel(red: Int(pixel[0]), green: Int(pixel[1]), blue: Int(pixel[2]))
    }
}

extension UIImage {
    /// Reads the pixel at (`x`, `y`) in pixels (not points), with the origin at the top left.
    func rgbPixel(x: Int, y: Int) throws -> RGBPixel {
        guard let cgImage else { throw PixelSamplingError.missingCGImage }
        return try cgImage.rgbPixel(x: x, y: y)
    }
}

extension CVPixelBuffer {
    var pixelSize: CGSize {
        CGSize(width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))
    }

    /// Reads the pixel at (`x`, `y`) from a 32BGRA buffer, with the origin at the top left.
    func rgbPixel(x: Int, y: Int) throws -> RGBPixel {
        guard x >= 0, y >= 0, x < CVPixelBufferGetWidth(self), y < CVPixelBufferGetHeight(self),
              CVPixelBufferGetPixelFormatType(self) == kCVPixelFormatType_32BGRA else {
            throw PixelSamplingError.outOfBounds
        }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(self) else {
            throw PixelSamplingError.contextCreationFailed
        }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let offset = y * CVPixelBufferGetBytesPerRow(self) + x * 4
        return RGBPixel(red: Int(bytes[offset + 2]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset]))
    }

    /// The buffer's visible pixel bytes, row by row, ignoring row padding.
    func pixelBytes() -> [UInt8] {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(self) else { return [] }

        let rowLength = CVPixelBufferGetWidth(self) * 4
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        var result = [UInt8]()
        result.reserveCapacity(rowLength * CVPixelBufferGetHeight(self))
        for row in 0..<CVPixelBufferGetHeight(self) {
            let rowStart = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            result.append(contentsOf: UnsafeBufferPointer(start: rowStart, count: rowLength))
        }
        return result
    }
}
