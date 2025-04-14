import SwiftUI

public struct DualCameraDisplayView: View {
    private let controller: DualCameraControlling
    private let layout: DualCameraLayout
    
    public init(
        controller: DualCameraControlling,
        layout: DualCameraLayout = .piP(
            miniCamera: .front,
            miniCameraPosition: .bottomTrailing
        )
    ) {
        self.controller = controller
        self.layout = layout
    }
    
    public var body: some View {
        Group {
            switch layout {
            case .piP(let miniCamera, let position):
                // A single ZStack with dynamic alignment for PiP
                ZStack(alignment: position.alignment()) {
                    // Background camera
                    DualCameraRendererView(
                        renderer: controller.getRenderer(
                            for: (miniCamera == .front ? .back : .front)
                        )
                    )
//                    .ignoresSafeArea(.all)
                    
                    // Mini camera in corner
                    DualCameraRendererView(renderer: controller.getRenderer(for: miniCamera))
                        .frame(width: 150)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(10)
                        .padding(16)
                }
                
            case .sideBySide:
                HStack(spacing: 0) {
                    cameraView(for: .back, widthFraction: 0.5)
                    cameraView(for: .front, widthFraction: 0.5)
                }
//                .ignoresSafeArea(.all)
                
            case .stackedVertical:
                VStack(spacing: 0) {
                    cameraView(for: .back, heightFraction: 0.5)
                    cameraView(for: .front, heightFraction: 0.5)
                }
//                .ignoresSafeArea(.all)
            }
        }
        .task {
            // TODO: fixme - should View here depend on VM? this functionality led to bug in screen due to ctrl.startSession vs. vm.startSession
//            do {
//                try await controller.startSession()
//            } catch {
//                print("Camera session error: \(error)")
//            }
        }
    }
    
    /// Renders a camera feed in partial or full size
    @ViewBuilder
    private func cameraView(for source: DualCameraSource,
                            widthFraction: CGFloat? = nil,
                            heightFraction: CGFloat? = nil) -> some View {
        let rendererView = DualCameraRendererView(renderer: controller.getRenderer(for: source))
        
        if let widthFraction = widthFraction {
            rendererView
                .frame(width: UIScreen.main.bounds.width * widthFraction)
        } else if let heightFraction = heightFraction {
            rendererView
                .frame(height: UIScreen.main.bounds.height * heightFraction)
        } else {
            rendererView
        }
    }
}

#Preview("PiP - Bottom Trailing") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    )
}

#Preview("PiP - Bottom Leading") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .piP(miniCamera: .front, miniCameraPosition: .bottomLeading)
    )
}

#Preview("PiP - Top Trailing") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .piP(miniCamera: .front, miniCameraPosition: .topTrailing)
    )
}

#Preview("PiP - Top Leading") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .piP(miniCamera: .front, miniCameraPosition: .topLeading)
    )
}

#Preview("Stacked Vertical") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .stackedVertical
    )
}

#Preview("Side by Side") {
    DualCameraDisplayView(
        controller: DualCameraMockController(),
        layout: .sideBySide
    )
}
