import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    enum DemoDisplayType {
        case dualCameraScreen
        case dualCameraDisplayView
        case dualCameraLowLevelComponents
    }
    
    @State private var demoType = DemoDisplayType.dualCameraScreen
    
    var body: some Scene {
        WindowGroup {
            switch demoType {
            case .dualCameraScreen:
                DualCameraScreen(
                    initialLayout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
                    initialVideoRecorderMode: .replayKit(.init())
                )
            case .dualCameraDisplayView, .dualCameraLowLevelComponents:
                Text("Not Implemented Yet")
            }
            
        }
    }
}
