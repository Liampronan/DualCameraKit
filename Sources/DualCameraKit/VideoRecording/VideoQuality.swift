import AVFoundation

/// Determines the quality of the recorded video.
/// For now, we associate framerate with quality and there is no way to override.
/// In the future, we could make this adaptive and/or user-specificied
public enum VideoQuality: Sendable {
    /// 8 Mbps, 30 fps
    case medium
    /// 16 Mbps, 60 fps
    case high
    /// 24 Mbps, 60 fps
    case premium
    
    var bitrate: Int {
        switch self {
        case .medium: 8_000_000
        case .high: 16_000_000
        case .premium: 24_000_000
        }
    }
    
    var frameRate: Int {
        switch self {
        case .medium:  return 30
        case .high:    return 60
        case .premium: return 60
        }
    }
    
    var codecType: AVVideoCodecType {
        switch self {
        case .medium, .high: return .h264
        case .premium: return .hevc  // Only premium uses HEVC
        }
    }
    
    var profileLevel: String {
        switch self {
        case .medium:  return AVVideoProfileLevelH264MainAutoLevel
        case .high:    return AVVideoProfileLevelH264HighAutoLevel 
        case .premium: return AVVideoProfileLevelH264HighAutoLevel // Not used for HEVC
        }
    }
    
    var allowFrameReordering: Bool {
        switch self {
        case .medium:  return false
        case .high, .premium: return true
        }
    }
    
    var keyframeInterval: Double {
        switch self {
        case .medium:  return 3.0
        case .high:    return 2.0
        case .premium: return 1.0
        }
    }
}
