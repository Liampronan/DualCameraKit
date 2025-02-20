import DualCameraKit
import SwiftUI

struct ContentView: View {
    private let dualCameraManager = DualCameraManager()
    
    var body: some View {
        VStack {
            DualCameraScreen(
                dualCameraManager: dualCameraManager,
                initialLayout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
            )
        }
        .padding()
    }
}

//#Preview {
//    ContentView()
//}
