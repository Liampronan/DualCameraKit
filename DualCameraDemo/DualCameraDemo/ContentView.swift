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
        }
    }
}

//#Preview {
//    ContentView()
//}
