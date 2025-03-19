import DualCameraKit
import SwiftUI

@main
struct DualCameraDemoApp: App {
    
    let dualCameraController = {
        // for now, during development simple way to swap between video recorders
        let useReplaykitRecorder = false
        let photoCapturer = DualCameraPhotoCapturer()
        var videoRecorder: DualCameraVideoRecording
        
        if useReplaykitRecorder {
            videoRecorder = DualCameraReplayKitVideoRecorder()
        } else {
            let videoRecordingConfig = DualCameraCPUVideoRecorderConfig(
                mode: .screenCapture(.fullScreen),
                quality: .premium
            )
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
