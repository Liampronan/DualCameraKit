import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    @State private var controllerManager = ManagedDualCameraController()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controllerManager)
        }
    }
}

/// Manages the DualCameraController lifecycle and configuration
@Observable
@MainActor
final class ManagedDualCameraController {
    // Public state
    private(set) var controller: DualCameraControlling
    var recorderType: VideoRecorderType = .cpuBased {
        didSet {
            if oldValue != recorderType {
                updateController()
            }
        }
    }
    
    // Core dependencies
    private let photoCapturer = DualCameraPhotoCapturer()
    
    init() {
        // Create initial controller
        let videoRecorder = Self.createVideoRecorder(
            type: .cpuBased,
            photoCapturer: photoCapturer
        )
        
        self.controller = DualCameraController(
            videoRecorder: videoRecorder,
            photoCapturer: photoCapturer
        )
    }
    
    /// Updates the controller when configuration changes
    private func updateController() {
        // Clean up any existing resources
        controller.stopSession()
        
        // Create a new video recorder based on the current type
        let videoRecorder = Self.createVideoRecorder(
            type: recorderType,
            photoCapturer: photoCapturer
        )
        
        // Create a new controller
        controller = DualCameraController(
            videoRecorder: videoRecorder,
            photoCapturer: photoCapturer
        )
    }
    
    /// Factory method to create the appropriate video recorder
    private static func createVideoRecorder(
        type: VideoRecorderType,
        photoCapturer: DualCameraPhotoCapturing
    ) -> DualCameraVideoRecording {
        switch type {
        case .cpuBased:
            let config = DualCameraCPUVideoRecorderConfig(
                mode: .screenCapture(.fullScreen),
                quality: .premium
            )
            return DualCameraCPUVideoRecorderManager(
                photoCapturer: photoCapturer,
                config: config
            )
        case .replayKit:
            return DualCameraReplayKitVideoRecorder()
        }
    }
}
