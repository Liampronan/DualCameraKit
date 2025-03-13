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
                    layout: viewModel.state.cameraLayout
                )
                .overlay(recordingIndicator, alignment: .top)
                .overlay(controlButtons, alignment: .bottom)
                
                // Capture flash effect
                if viewModel.state.operationMode.isCapturing {
                    Color.white
                        .ignoresSafeArea()
                        .opacity(0.3)
                        .transition(.opacity)
                }
                
                // Captured image overlay
                if let capturedImage = viewModel.state.capturedImage {
                    capturedImageOverlay(capturedImage)
                        .transition(.opacity)
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
            .animation(.easeInOut(duration: 0.2), value: viewModel.state.operationMode.isCapturing)
            .animation(.easeInOut(duration: 0.3), value: viewModel.state.capturedImage != nil)
            .alert(
                item: $viewModel.state.alert
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
        if viewModel.state.operationMode.isRecording {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.8)
                
                Text(viewModel.formatDuration(viewModel.state.operationMode.recordingDuration))
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
            .disabled(!viewModel.state.operationMode.isIdle)
            
            // Video recording button
            Button(action: viewModel.toggleRecording) {
                Image(systemName: viewModel.state.operationMode.isRecording ? "stop.fill" : "record.circle")
                    .font(.largeTitle)
                    .foregroundColor(viewModel.state.operationMode.isRecording ? .red : .white)
                    .padding()
                    .background(
                        Circle()
                            .fill(viewModel.state.operationMode.isRecording ? Color.white.opacity(0.8) : Color.black.opacity(0.5))
                    )
            }
            .disabled(viewModel.state.operationMode.isCapturing)
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
                .ignoresSafeArea(.all)
            
            VStack {
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
        .ignoresSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
