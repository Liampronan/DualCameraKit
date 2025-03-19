import DualCameraKit
import SwiftUI

@main
struct DualCameraDemoApp: App {
    
    let dualCameraController = {
        // for now, during development simple way to swap between video recorders
        let useReplaykitRecorder = true
        let photoCapturer = DualCameraPhotoCapturer()
//        let videoRecorder: DualCameraVideoRecording2 = useReplaykitRecorder ? ReplayKitVideoRecorder() : CPUIntensiveVideoRecorder(photoCapturer: photoCapturer)
        let videoRecordingConfig = DualCameraCPUVideoRecorderConfig(
            mode: .screenCapture(.fullScreen),
            quality: .high
        )
        var videoRecorder: DualCameraVideoRecording
        
        if useReplaykitRecorder {
            videoRecorder = DualCameraReplayKitVideoRecorder()
        } else {
            videoRecorder = DualCameraCPUVideoRecorderManager(photoCapturer: photoCapturer, config: videoRecordingConfig)
        }
        return DualCameraController(videoRecorder: videoRecorder, photoCapturer: photoCapturer)
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView(dualCameraController: dualCameraController)
        }
    }
}
