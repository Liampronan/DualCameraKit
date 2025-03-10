import SwiftUI

public struct DualCameraScreen: View {
    private let controller: DualCameraController
    private let layout: CameraLayout
    
    public init(
        controller: DualCameraController,
        layout: CameraLayout = .fullScreenWithMini(
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
            case .fullScreenWithMini(let miniCamera, let position):
                // A single ZStack with dynamic alignment for PiP
                ZStack(alignment: position.alignment()) {
                    // Background camera
                    RendererView(
                        renderer: controller.getRenderer(
                            for: (miniCamera == .front ? .back : .front)
                        )
                    )
                    .ignoresSafeArea(.all)
                    
                    // Mini camera in corner
                    RendererView(renderer: controller.getRenderer(for: miniCamera))
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
                .ignoresSafeArea(.all)
                
            case .stackedVertical:
                VStack(spacing: 0) {
                    cameraView(for: .back, heightFraction: 0.5)
                    cameraView(for: .front, heightFraction: 0.5)
                }
                .ignoresSafeArea(.all)
            }
        }
       
        .task {
            do {
                try await controller.startSession()
            } catch {
                print("Camera session error: \(error)")
            }
        }
    }
    
    /// Renders a camera feed in partial or full size
    @ViewBuilder
    private func cameraView(for source: CameraSource,
                            widthFraction: CGFloat? = nil,
                            heightFraction: CGFloat? = nil) -> some View {
        let rendererView = RendererView(renderer: controller.getRenderer(for: source))
        
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

public enum CameraSource {
    case front, back
}
