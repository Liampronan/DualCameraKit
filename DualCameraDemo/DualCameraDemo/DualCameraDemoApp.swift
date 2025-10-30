import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    enum DemoDisplayType {
        case dualCameraScreen(isFullScreen: Bool)
        case dualCameraDisplayView
        case dualCameraLowLevelComponents
    }
    
    @State private var demoType = DemoDisplayType.dualCameraScreen(isFullScreen: false)
    
    var body: some Scene {
        WindowGroup {
            switch demoType {
            case .dualCameraScreen(let isFullScreen):
                switch isFullScreen {
                case true:
                    DualCameraScreen()
                case false:
                    ContainerExample()
                }
            case .dualCameraDisplayView, .dualCameraLowLevelComponents:
                Text("Not Implemented Yet")
            }
        }
    }
}
