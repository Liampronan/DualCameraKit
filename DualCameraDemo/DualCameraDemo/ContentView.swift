import DualCameraKit
import SwiftUI

struct ContentView: View {
    private let dualCameraController = DualCameraController()
    
    var body: some View {
        VStack {
            DualCameraScreen(
                controller: dualCameraController,
                layout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
            )
//            .toolbar {
//                ToolbarItem(placement: .bottomBar) {
//                    Button("Capture") {
//                        Task {
//                            if let image = try? await dualCameraController.capturePhoto() {
//                                // Handle captured image
//                                print(image)
//                            }
//                        }
//                    }
//                }
//            }
        }
    }
}

//#Preview {
//    ContentView()
//}
