import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    
// mock implementation for simulators – since there is no camera in simulator.
#if targetEnvironment(simulator)
    var dualCameraController = DualCameraMockController()
#else
    var dualCameraController = DualCameraController()
#endif
    
    var body: some Scene {
        WindowGroup {
            ContentView(dualCameraController: dualCameraController)
        }
    }
}
