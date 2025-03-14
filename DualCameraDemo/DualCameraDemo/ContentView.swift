import DualCameraKit
import SwiftUI
import Photos

struct ContentView: View {
    @State private var viewModel = DualCameraViewModel()
    
    var body: some View {
        GeometryReader { geoProxy in
            ZStack {
                // Main camera view
                DualCameraScreen(
                    controller: viewModel.dualCameraController,
                    layout: viewModel.configuration.layout
                )
                .overlay(recordingIndicator, alignment: .top)
                .overlay(controlButtons, alignment: .bottom)
                
                // Capture flash effect
                if case .capturing = viewModel.viewState {
                    Color.white
                        .ignoresSafeArea()
                        .opacity(0.3)
                        .transition(.opacity)
                }
                
                // Captured image overlay
                if let capturedImage = viewModel.capturedImage {
                    capturedImageOverlay(capturedImage)
                        .transition(.opacity)
                }
                
                // Error overlay for critical errors
                if case .error(let error) = viewModel.viewState {
                    errorOverlay(error)
                }
            }
            .onChange(of: geoProxy.size, initial: true) { oldSize, newSize in
                viewModel.containerSizeChanged(newSize)
            }
            .onAppear {
                viewModel.onAppear(containerSize: geoProxy.size)
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.viewState)
            .animation(.easeInOut(duration: 0.3), value: viewModel.capturedImage != nil)
            .alert(
                item: $viewModel.alert
            ) { alert in
                if let secondaryButton = alert.secondaryButton {
                    return Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text(alert.primaryButton.text), action: alert.primaryButton.action),
                        secondaryButton: .cancel(Text(secondaryButton.text), action: secondaryButton.action)
                    )
                } else {
                    return Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text(alert.primaryButton.text), action: alert.primaryButton.action)
                    )
                }
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var recordingIndicator: some View {
        if case .recording(let state) = viewModel.viewState {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.8)
                
                Text(state.formattedDuration)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
            .padding(.top, 40)
        }
    }
    
    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 30) {
            // Photo capture button
            Button(action: viewModel.takePhoto) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding()
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .disabled(!viewModel.viewState.isPhotoButtonEnabled)
            
            // Video recording button
            Button(action: viewModel.toggleRecording) {
                Image(systemName: viewModel.viewState.videoButtonIcon)
                    .font(.largeTitle)
                    .foregroundColor(viewModel.viewState.videoButtonColor)
                    .padding()
                    .background(
                        Circle()
                            .fill(viewModel.viewState.videoButtonBackgroundColor)
                    )
            }
            .disabled(!viewModel.viewState.isVideoButtonEnabled)
            
            // Layout picker button (optional - allows changing camera layout)
            Menu {
                Button("Side by Side") {
                    viewModel.updateLayout(.sideBySide)
                }
                
                Button("Stacked Vertical") {
                    viewModel.updateLayout(.stackedVertical)
                }
                
                Menu("PiP Mode") {
                    Button("Front Mini - Top Left") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .topLeading))
                    }
                    
                    Button("Front Mini - Top Right") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .topTrailing))
                    }
                    
                    Button("Front Mini - Bottom Left") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomLeading))
                    }
                    
                    Button("Front Mini - Bottom Right") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing))
                    }
                    
                    Divider()
                    
                    Button("Back Mini - Top Left") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .back, miniCameraPosition: .topLeading))
                    }
                    
                    Button("Back Mini - Top Right") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .back, miniCameraPosition: .topTrailing))
                    }
                    
                    Button("Back Mini - Bottom Left") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .back, miniCameraPosition: .bottomLeading))
                    }
                    
                    Button("Back Mini - Bottom Right") {
                        viewModel.updateLayout(.fullScreenWithMini(miniCamera: .back, miniCameraPosition: .bottomTrailing))
                    }
                }
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .disabled(!viewModel.viewState.isPhotoButtonEnabled)
        }
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    private func capturedImageOverlay(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button(action: viewModel.dismissCapturedImage) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        // Save to photo library action would go here
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding()
                
                Spacer()
                
                Button("Dismiss") {
                    viewModel.dismissCapturedImage()
                }
                .padding()
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .foregroundColor(.white)
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func errorOverlay(_ error: DualCameraError) -> some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.yellow)
                
                Text("Camera Error")
                    .font(.title)
                    .foregroundColor(.white)
                
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Show specific hint based on error type
                if case .permissionDenied = error {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding()
                    .background(Capsule().fill(Color.blue))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                }
            }
            .padding(30)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
