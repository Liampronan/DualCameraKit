import DualCameraKit
import SwiftUI

@main
struct DualCameraDemoApp: App {
    
    let dualCameraController = {
        // for now, during development simple way to swap between video recorders
        let useReplaykitRecorder = false
        let photoCapturer = DualCameraPhotoCapturer()
        let videoRecorder: DualCameraVideoRecording = useReplaykitRecorder ? ReplayKitVideoRecorder() : CPUIntensiveVideoRecorder(photoCapturer: photoCapturer)
        return DualCameraController(videoRecorder: videoRecorder, photoCapturer: photoCapturer)
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView(dualCameraController: dualCameraController)
        }
    }
}
