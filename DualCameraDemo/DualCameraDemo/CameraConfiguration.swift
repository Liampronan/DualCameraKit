import DualCameraKit
import Foundation

/// Configuration options that persist across state changes
struct CameraConfiguration: Equatable {
    var layout: CameraLayout = .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    var containerSize: CGSize = .zero
    var videoRecorderType: VideoRecorderType = .cpuBased
}

enum VideoRecorderType: String, CaseIterable, Identifiable {
    case cpuBased
    case replayKit
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .cpuBased: "CPU Recorder"
        case .replayKit: "ReplayKit"
        }
    }
}
