import SwiftUI

public struct DualCameraScreen: View {
    private let controller: DualCameraController
    private let layout: CameraLayout
    @State private var demoImage: UIImage?
    @State private var containerSize: CGSize = .zero
    
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
        GeometryReader { geometry in
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
                        .edgesIgnoringSafeArea(.all)
                        
                        // Mini camera in corner
                        RendererView(renderer: controller.getRenderer(for: miniCamera))
                            .frame(width: 150)
                            .aspectRatio(16/9, contentMode: .fit)
                            .cornerRadius(10)
                            .padding(16)
                    }
                    .overlay(captureButton(), alignment: .center)

                case .sideBySide:
                    HStack(spacing: 0) {
                        cameraView(for: .back, widthFraction: 0.5)
                        cameraView(for: .front, widthFraction: 0.5)
                    }
                    .edgesIgnoringSafeArea(.all)
                    .overlay(captureButton(), alignment: .center)

                case .stackedVertical:
                    VStack(spacing: 0) {
                        cameraView(for: .back, heightFraction: 0.5)
                        cameraView(for: .front, heightFraction: 0.5)
                    }
                    .edgesIgnoringSafeArea(.all)
                    .overlay(captureButton(), alignment: .center)
                }
            }
        }
        // Show the captured image if any
        .overlay {
            if let demoImage {
                ZStack {
                    Image(uiImage: demoImage)
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
    
    /// Simple capture button overlay
    @ViewBuilder
    private func captureButton() -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: takePhoto) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding()
            }
        }
    }
    
    private func takePhoto() {
        let c = controller
        let l = layout
        Task { @MainActor in
            do {
                demoImage = try await c.capturePhotoWithLayout(l, containerSize: containerSize)
                print("Captured image: \(String(describing: demoImage))")
            } catch {
                print("Error capturing photo: \(error)")
            }
        }
    }
}

/// Defines different layouts for dual-camera display
public enum CameraLayout: Equatable, Hashable {
    case sideBySide
    case stackedVertical
    case fullScreenWithMini(miniCamera: CameraSource, miniCameraPosition: MiniCameraPosition)

    public enum MiniCamera: CaseIterable, Equatable, Hashable {
        case front, back
    }
    
    /// Positions for mini camera
    public enum MiniCameraPosition: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        
        func alignment() -> Alignment {
            switch self {
            case .topLeading:     return .topLeading
            case .topTrailing:    return .topTrailing
            case .bottomLeading:  return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }
}

public enum CameraSource {
    case front, back
}
