import DualCameraKit
import SwiftUI

struct ContentView: View {
    @State private var layout = CameraLayout.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    @State private var containerSize: CGSize = .zero
    @State private var demoImage: UIImage?
    @State private var isCapturing = false
    private let dualCameraController = DualCameraController()
    
    var body: some View {
        GeometryReader { geoProxy in
            VStack {
                DualCameraScreen(
                    controller: dualCameraController,
                    layout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
                )
                .overlay(captureButton(), alignment: .center)
            }
            .onChange(of: geoProxy.size, initial: true) { _, newSize in
                containerSize = newSize
            }
            .onAppear {
                containerSize = geoProxy.size
                
                // Start camera session when view appears
                Task {
                    try? await dualCameraController.startSession()
                }
            }
            .onDisappear {
                // Stop camera session when view disappears
                dualCameraController.stopSession()
            }
            
            // Show the captured image if any
            .overlay {
                if let demoImage {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: demoImage)
                            .ignoresSafeArea(.all)
                        
                        VStack {
                            Spacer()
                            Button("Dismiss") {
                                self.demoImage = nil
                            }
                            .padding()
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                        }
                    }
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
                }
            }
            .overlay {
                if isCapturing {
                    // Flash effect for camera capture
                    Color.white
                        .ignoresSafeArea()
                        .opacity(0.3)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isCapturing)
            .animation(.easeInOut(duration: 0.3), value: demoImage != nil)
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
                .disabled(isCapturing)
            }
        }
    }
    
    @MainActor
    private func takePhoto() {
        Task {
            guard !isCapturing else { return }
            
            isCapturing = true
            defer { isCapturing = false }
            
            do {
                // Flash effect
                withAnimation {
                    isCapturing = true
                }
                
                // Capture screen
                demoImage = try await dualCameraController.captureCurrentScreen()
                print("Captured image: \(containerSize)")
                
                // End flash effect
                withAnimation {
                    isCapturing = false
                }
            } catch {
                print("Error capturing photo: \(error)")
                
                // End flash effect
                withAnimation {
                    isCapturing = false
                }
            }
        }
    }
}
