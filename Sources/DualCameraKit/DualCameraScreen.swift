import SwiftUI

public struct DualCameraScreen: View {
    private let controller: DualCameraController
    private let layout: CameraLayout
    
    @State private var image: UIImage?
    
    // Map camera source to renderer
    @State private var renderers: [CameraSource: CameraRenderer] = [:]
    // Store tasks to prevent cancellation
    @State private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    public init(
        controller: DualCameraController,
        layout: CameraLayout = .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    ) {
        self.controller = controller
        self.layout = layout
    }
    
    public var body: some View {
        ZStack {
            switch layout {
            case .fullScreenWithMini(let miniCamera, let position):
                ZStack {
                    cameraView(for: miniCamera == .front ? .back : .front, isFullscreen: true)
                    cameraView(for: miniCamera, isFullscreen: false, position: position)
                    if let image { Image(uiImage: image).resizable().scaledToFit() } 
                }
            case .sideBySide:
                HStack(spacing: 0) {
                    cameraView(for: .back, widthFraction: 0.5)
                    cameraView(for: .front, widthFraction: 0.5)
                }
            case .stackedVertical:
                VStack(spacing: 0) {
                    cameraView(for: .back, heightFraction: 0.5)
                    cameraView(for: .front, heightFraction: 0.5)
                }
            }
            
            // Controls overlay
            captureButton()
        }
        .edgesIgnoringSafeArea(.all)
        .task {
            do {
                try await controller.startSession()
                // Rest of code...
            } catch {
                print("Camera session error: \(error)")
                return
                // Surface error to UI
            }
            
            // Initialize all renderers on first load
            let backRenderer = controller.createRenderer()
            let frontRenderer = controller.createRenderer()
            
            // Update state on main thread
            await MainActor.run {
                renderers[.back] = backRenderer
                renderers[.front] = frontRenderer
                
                // Set primary renderer
                controller.setPrimaryRenderer(backRenderer)
                controller.setRenderers(backRenderer, frontRenderer)
                
                // Start camera streams
                connectCameraStream(for: .back)
                connectCameraStream(for: .front)
            }
        }
        .onDisappear {
            // Cancel all stream tasks
            for task in streamTasks.values {
                task.cancel()
            }
            streamTasks = [:]
            renderers = [:]
        }
    }
    
    private func connectCameraStream(for source: CameraSource) {
        // Cancel existing task
        streamTasks[source]?.cancel()
        
        // Create and store new task with debug info
        let task = Task {
            guard let renderer = renderers[source] else {
                print("⚠️ Camera error: No renderer for \(source)")
                return
            }
            
            let stream = source == .front ? controller.frontCameraStream : controller.backCameraStream
            var frameCount = 0
            
            for await buffer in stream {
                if Task.isCancelled { break }
//                frameCount += 1
//                if frameCount % 30 == 0 {
//                    print("✅ Camera \(source): received frame #\(frameCount)")
//                }
                renderer.update(with: buffer.buffer)
            }
        }
        
        streamTasks[source] = task
    }
    
    @ViewBuilder
    private func cameraView(for source: CameraSource,
                           isFullscreen: Bool = true,
                           position: CameraLayout.MiniCameraPosition? = nil,
                           widthFraction: CGFloat? = nil,
                           heightFraction: CGFloat? = nil) -> some View {
        // Use ZStack with conditional rendering
        ZStack {
            if let renderer = renderers[source] {
                RendererView(renderer: renderer)
                    .modifier(CameraViewModifier(
                        isFullscreen: isFullscreen,
                        position: position,
                        widthFraction: widthFraction,
                        heightFraction: heightFraction
                    ))
            } else {
                Color.black
                    .modifier(CameraViewModifier(
                        isFullscreen: isFullscreen,
                        position: position,
                        widthFraction: widthFraction,
                        heightFraction: heightFraction
                    ))
            }
        }
    }

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
                Spacer()
            }
        }
    }
    
    // START:
    // √1. fix photo capture
    // √2. debug slowness
    // 3. refactor - CameraRenderer excess
    // 4. refactor - this flow in DualCameraScreen; feels like a setup layer could help; see connectCameraStream
    // 5. refactor - general
    // 6. pass layout to camera capture
    private func takePhoto() {
        let controllerRef = controller
        Task { @MainActor in
            do {
                image = try await controllerRef.captureCombinedPhoto()
            } catch {
                print("Error capturing photo: \(error)")
            }
        }
    }
}

struct CameraViewModifier: ViewModifier {
    let isFullscreen: Bool
    let position: CameraLayout.MiniCameraPosition?
    let widthFraction: CGFloat?
    let heightFraction: CGFloat?
    
    func body(content: Content) -> some View {
        if isFullscreen {
            return AnyView(content)
        } else if let position = position {
            let size = CGSize(width: 150, height: 200)
            return AnyView(content
                .frame(width: size.width, height: size.height)
                .cornerRadius(10)
                .positioned(in: position, size: size, padding: 16))
        } else if let widthFraction = widthFraction {
            return AnyView(content.frame(width: UIScreen.main.bounds.width * widthFraction))
        } else if let heightFraction = heightFraction {
            return AnyView(content.frame(height: UIScreen.main.bounds.height * heightFraction))
        } else {
            return AnyView(content)
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
    
    /// Defines positions where the mini camera can be placed.
    public enum MiniCameraPosition: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// Returns the appropriate offset for the given position
        func offset(for size: CGSize, padding: CGFloat) -> CGSize {
            switch self {
            case .topLeading:
                return CGSize(width: -size.width / 2 - padding, height: -size.height / 2 - padding)
            case .topTrailing:
                return CGSize(width: size.width / 2 + padding, height: -size.height / 2 - padding)
            case .bottomLeading:
                return CGSize(width: -size.width / 2 - padding, height: size.height / 2 + padding)
            case .bottomTrailing:
                return CGSize(width: size.width / 2 + padding, height: size.height / 2 + padding)
            }
        }

        /// Returns the appropriate alignment for SwiftUI `.position`
        func alignment() -> Alignment {
            switch self {
            case .topLeading:
                return .topLeading
            case .topTrailing:
                return .topTrailing
            case .bottomLeading:
                return .bottomLeading
            case .bottomTrailing:
                return .bottomTrailing
            }
        }
    }
}

public enum CameraSource {
    case front, back
}


///// PiP camera position
//public enum MiniCameraPosition: CaseIterable {
//    case topLeading, topTrailing, bottomLeading, bottomTrailing
//}

/// Camera layout configuration
//public enum CameraLayout {
//    case sideBySide
//    case stackedVertical
//    case fullScreenWithMini(miniCamera: CameraSource, miniCameraPosition: MiniCameraPosition)
//}


// TODO: figure out preview strategy here - mock streams
//#Preview {
//    VStack {
//        DualCameraView(initialLayout: .sideBySide)
//        DualCameraView(initialLayout: .stackedVertical)
//        DualCameraView(initialLayout: .fullScreenWithMini(miniCamera: .front))
//    }
//}
