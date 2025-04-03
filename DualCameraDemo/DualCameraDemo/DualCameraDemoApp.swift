import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    enum DemoDisplayType {
        case dualCameraScreen(photoCaptureMode: DualCameraPhotoCaptureMode)
        case dualCameraDisplayView
        case dualCameraLowLevelComponents
    }
    
    @State private var demoType = DemoDisplayType.dualCameraScreen(photoCaptureMode: .fullScreen)
    
    var body: some Scene {
        WindowGroup {
            switch demoType {
            case .dualCameraScreen(let photoCaptureMode):
                switch photoCaptureMode {
                case .fullScreen:
                    DualCameraScreen()
                case .containerSize(let cGSize):
                    ContainerExample()
                }
                
            
            case .dualCameraDisplayView, .dualCameraLowLevelComponents:
                Text("Not Implemented Yet")
            }
            
        }
    }
}
