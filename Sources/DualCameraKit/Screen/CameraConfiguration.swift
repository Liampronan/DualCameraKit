import Foundation

/// Configuration options that persist across state changes
struct CameraConfiguration: Equatable {
    var layout: CameraLayout
    var containerSize: CGSize
    var videoRecorderType: DualCameraVideoRecorderType
    
    init(layout: CameraLayout  = .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing), containerSize: CGSize  = .zero, videoRecorderType: DualCameraVideoRecorderType = .cpuBased(DualCameraCPUVideoRecorderConfig(mode: .fullScreen))) {
        self.layout = layout
        self.containerSize = containerSize
        self.videoRecorderType = videoRecorderType
    }
}
