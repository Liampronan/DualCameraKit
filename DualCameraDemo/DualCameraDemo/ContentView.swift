import DualCameraKit
import SwiftUI
import Photos

struct ContentView: View {
    @State private var viewModel: DualCameraViewModel
    
    init(dualCameraController: DualCameraControlling) {
        _viewModel = State(initialValue: DualCameraViewModel(dualCameraController: dualCameraController))

    }
    
    var body: some View {
        GeometryReader { geoProxy in
            ZStack {
                // Main camera view
                DualCameraScreen(
                    controller: viewModel.controller,
                    layout: viewModel.configuration.layout
                )
                .overlay(recordingIndicator, alignment: .top)
                .overlay(controlButtons, alignment: .bottom)
                
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
        VStack(spacing: 16) {
            // Video recorder type picker
            recorderTypePicker
            
            HStack(spacing: 32) {
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
        }
        .opacity(viewModel.viewState.captureInProgress ? 0 : 1) 
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    private var recorderTypePicker: some View {
        VStack {
            Menu {
                ForEach(DualCameraVideoRecorderType.allCases) { recorderType in
                    Button {
                        viewModel.toggleRecorderType()
                    } label: {
                        HStack {
                            Text(recorderType.displayName)
                            if viewModel.videoRecorderType == recorderType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Recorder: \(viewModel.videoRecorderType.displayName)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .foregroundColor(.white)
            }
        }
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

#Preview() {
    ContentView(dualCameraController: DualCameraMockController())
}
