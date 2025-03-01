import SwiftUI

/// Defines different layouts for dual-camera display
public enum CameraLayout: Equatable, Hashable {
    case sideBySide
    case stackedVertical
    case fullScreenWithMini(miniCamera: CameraSource, miniCameraPosition: MiniCameraPosition)

    public enum MiniCamera: CaseIterable, Equatable, Hashable {
        case front, back
    }
    
    /// Positions for mini camera
    public enum MiniCameraPosition: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        
        func alignment() -> Alignment {
            switch self {
            case .topLeading:     return .topLeading
            case .topTrailing:    return .topTrailing
            case .bottomLeading:  return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }
}
