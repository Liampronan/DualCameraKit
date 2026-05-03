import DualCameraKit
import DualCameraKitUI
import Observation
import SwiftUI

@main 
struct DualCameraDemoApp: App {
    enum DemoDisplayType: String, CaseIterable, Identifiable {
        case dropIn = "Drop-in"
        case container = "Container"
        case compositional = "Compositional"

        var id: String { rawValue }
    }
    
    @State private var demoType = DemoDisplayType.container
    
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Picker("Demo", selection: $demoType) {
                    ForEach(DemoDisplayType.allCases) { demo in
                        Text(demo.rawValue).tag(demo)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch demoType {
                case .dropIn:
                    DualCameraScreen()
                case .container:
                    ContainerExample()
                case .compositional:
                    CompositionalExample()
                }
            }
        }
    }
}
