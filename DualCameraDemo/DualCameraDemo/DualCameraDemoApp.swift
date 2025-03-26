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
                    layout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
                )
            case .dualCameraDisplayView, .dualCameraLowLevelComponents:
                Text("Not Implemented Yet")
            }
            
        }
    }
}
