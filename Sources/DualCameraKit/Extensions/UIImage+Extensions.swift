import AVFoundation 
import UIKit

// MARK: - UIImage Extension for Video Recording
extension UIImage {
    /// Converts UIImage to CVPixelBuffer for video recording with optimized performance
    func pixelBuffer() -> CVPixelBuffer? {
        // First, try to get the CGImage for more direct conversion
        guard let cgImage = self.cgImage else {
            // Fallback to slower path if no CGImage is available
            return createPixelBufferFromUIImage()
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create pixel buffer with optimized settings for video recording
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:], // Using IOSurface for better performance
            kCVPixelBufferMetalCompatibilityKey as String: true  // Enable Metal compatibility for GPU processing
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA, // BGRA is more efficient for video encoding
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        // Lock buffer and ensure it gets unlocked
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags.init(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags.init(rawValue: 0)) }
        
        // Get context and render the image
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        if let context = context {
            // Use high-quality rendering for better output (this is optional and can be removed if too slow)
            context.interpolationQuality = .high
            
            // Draw the image - note that CGImage doesn't need y-flipping like UIImage does
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.draw(cgImage, in: rect)
        }
        
        return buffer
    }
    
    /// Fallback method using UIImage drawing when CGImage is not available
    private func createPixelBufferFromUIImage() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        if let context = context {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            
            UIGraphicsPushContext(context)
            draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
        }
        
        return buffer
    }
}
