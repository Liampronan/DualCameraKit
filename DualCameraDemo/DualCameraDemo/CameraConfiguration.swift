import DualCameraKit
import Foundation

/// Configuration options that persist across state changes
struct CameraConfiguration: Equatable {
    var layout: CameraLayout = .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    var containerSize: CGSize = .zero
    var videoRecorderType: DualCameraVideoRecorderType = .cpuBased(DualCameraCPUVideoRecorderConfig(mode: .fullScreen))
}
