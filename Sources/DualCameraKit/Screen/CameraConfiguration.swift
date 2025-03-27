import Foundation

/// Configuration options that persist across state changes
struct CameraConfiguration: Equatable {
    var layout: DualCameraLayout
    var containerSize: CGSize
    var videoRecorderMode: DualCameraVideoRecordingMode
    
    init(layout: DualCameraLayout  = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing), containerSize: CGSize  = .zero, videoRecorderMode: DualCameraVideoRecordingMode = .cpuBased(DualCameraCPUVideoRecorderConfig(photoCaptureMode: .fullScreen))) {
        self.layout = layout
        self.containerSize = containerSize
        self.videoRecorderMode = videoRecorderMode
    }
}
