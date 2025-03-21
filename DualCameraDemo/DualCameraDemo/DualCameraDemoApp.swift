import DualCameraKit
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    var dualCameraController = DualCameraController()
    
    var body: some Scene {
        WindowGroup {
            ContentView(dualCameraController: dualCameraController)
//                .environment(controllerManager)
        }
    }
}
