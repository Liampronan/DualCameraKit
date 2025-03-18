import AVFoundation
import CoreVideo

struct VideoRecorderSettingsFactory {
    /// Creates video encoding settings dictionary based on quality parameters
    /// - Parameters:
    ///   - quality: The video quality tier (medium, high, premium)
    ///   - dimensions: The video dimensions (width x height)
    /// - Returns: Dictionary with AVFoundation video settings
    static func createEncodingSettings(
        quality: VideoQuality,
        dimensions: CGSize
    ) -> [String: Any] {
        
        // Configure video compression properties
        var videoCompressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: quality.bitrate,
            AVVideoExpectedSourceFrameRateKey: quality.frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: quality.keyframeInterval,
            AVVideoAllowFrameReorderingKey: quality.allowFrameReordering
        ]
        
        // Add codec-specific settings
        if quality.codecType == .h264 {
            videoCompressionProperties[AVVideoProfileLevelKey] = quality.profileLevel
            videoCompressionProperties[AVVideoMaxKeyFrameIntervalKey] = quality.frameRate
        }
        
        // Create the final video settings dictionary
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: quality.codecType,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: videoCompressionProperties
        ]
        
        return videoSettings
    }
    
    /// Creates pixel buffer attributes for the given dimensions
    /// - Parameter dimensions: The video dimensions
    /// - Returns: Dictionary with pixel buffer attributes
    static func createPixelBufferAttributes(dimensions: CGSize) -> [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(dimensions.width),
            kCVPixelBufferHeightKey as String: Int(dimensions.height)
        ]
    }
}
