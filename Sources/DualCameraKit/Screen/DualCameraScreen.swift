import SwiftUI

public struct DualCameraScreen: View {
    @State private var viewModel: DualCameraViewModel
    
    // mock implementation for simulators – since there is no camera in simulator.
#if targetEnvironment(simulator)
    private var dualCameraController = DualCameraMockController()
#else
    private var dualCameraController = DualCameraController()
#endif

    public init(
        initialLayout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
        initialVideoRecorderMode: DualCameraVideoRecordingMode = .cpuBased(.init(mode: .fullScreen))
    ) {
        _viewModel = State(initialValue: DualCameraViewModel(
                dualCameraController: dualCameraController,
                layout: initialLayout,
                videoRecorderMode: initialVideoRecorderMode
            )
        )
    }
        
    public var body: some View {
        GeometryReader { geoProxy in
            ZStack {
                DualCameraDisplayView(
                    controller: viewModel.controller,
                    layout: viewModel.configuration.layout
                )
                .overlay(settingsButton, alignment: .topLeading)
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
            .sheet(item: $viewModel.presentedSheet, content: { sheetType in
                switch sheetType {
                case .configSheet: DualCameraConfigView(
                    viewModel: viewModel
                )
                }
            })
            .alert(
                item: $viewModel.alert
            ) { alert in
                getAlert(for: alert)
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
            .onTapGesture {
                viewModel.recordVideoButtonTapped()
            }
        }
    }
    
    @ViewBuilder
    private var controlButtons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                // Photo capture button
                Button(action: viewModel.capturePhotoButtonTapped) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .disabled(!viewModel.viewState.isPhotoButtonEnabled)
                
                // Video recording button
                Button(action: viewModel.recordVideoButtonTapped) {
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
            }
        }
        .opacity(viewModel.viewState.captureInProgress ? 0 : 1) 
        .padding(.bottom, 30)
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
    
    private func getAlert(for alertState: AlertState) -> Alert {
        if let secondaryButton = alertState.secondaryButton {
            return Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
                primaryButton: .default(Text(alertState.primaryButton.text), action: alertState.primaryButton.action),
                secondaryButton: .cancel(Text(secondaryButton.text), action: secondaryButton.action)
            )
        } else {
            return Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
                dismissButton: .default(Text(alertState.primaryButton.text), action: alertState.primaryButton.action)
            )
        }
    }
    
    private var settingsButton: some View {
        Button {
            viewModel.didTapConfigurationButton()
        } label: {
            Image(systemName: "gear")
                .font(.title2)
        }
        .tint(.gray)
        .padding(.leading)
    }
}

// MARK: - Preview

#Preview() {
    DualCameraScreen()
}
