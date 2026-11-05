import DualCameraKit
import SwiftUI
import UIKit

public struct DualCameraScreen: View {
    @Environment(\.displayScale) private var displayScale
    @State private var viewModel: DualCameraViewModel
    @State private var cameraDisplaySize: CGSize = .zero
    private let customOverlay: ((DualCameraViewModel) -> AnyView)

    @MainActor
    public init(
        viewModel: DualCameraViewModel? = nil,
        @ViewBuilder customOverlay: @escaping (DualCameraViewModel) -> some View = { _ in EmptyView() }
    ) {
        let resolvedViewModel = viewModel ?? .default()
        _viewModel = State(initialValue: resolvedViewModel)
        self.customOverlay = { AnyView(customOverlay($0)) }
    }

    public var body: some View {
        ZStack {
            // Capture is sized from the display view's own layout size, measured after
            // `.ignoresSafeArea()`, so the composed photo and its PiP placement match the
            // full-bleed preview. A GeometryReader around this ZStack would report the
            // safe-area size and the photo would come out shorter than the screen.
            DualCameraDisplayView(
                controller: viewModel.controller,
                layout: viewModel.cameraLayout,
                contentMode: viewModel.contentMode,
                onDisplaySizeChange: { newSize in
                    cameraDisplaySize = newSize
                    viewModel.containerSizeChanged(newSize)
                }
            )
            .ignoresSafeArea()
            .overlay(viewModel.isSettingsButtonVisible ? settingsButton : nil, alignment: .topLeading)
            .overlay(controlButtons, alignment: .bottom)
            .overlay(accessoryItems, alignment: .trailing)

            if case .error(let error) = viewModel.viewState {
                errorOverlay(error)
            }
        }
        .onAppear {
            viewModel.onAppear(containerSize: cameraDisplaySize, displayScale: displayScale)
        }
        .onChange(of: displayScale, initial: true) { _, newScale in
            viewModel.displayScaleChanged(newScale)
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.viewState)
        .sheet(item: $viewModel.presentedSheet, content: { sheetType in
            switch sheetType {
            case .configSheet:
                DualCameraConfigView(viewModel: viewModel)
            }
        })
        .alert(
            item: $viewModel.alert
        ) { alert in
            getAlert(for: alert)
        }
        .overlay(alignment: .top) {
            customOverlay(viewModel)
        }
    }

    // MARK: - View Components
    private var accessoryItems: some View {
        VStack {
            if viewModel.showCameraFlashButton {
                Button {
                    viewModel.toggleFlashButtonTapped()
                } label: {
                    Image(systemName: viewModel.flashMode.systemImageName)
                }
            }
        }
        .font(.largeTitle)
        .tint(.primary)
        .foregroundStyle(.white, .primary.opacity(0.5))
        .padding(.horizontal)
        .opacity(viewModel.viewState.captureInProgress ? 0 : 1.0)
    }

    @ViewBuilder
    private var controlButtons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                Button {
                    viewModel.capturePhotoButtonTapped()
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .disabled(!viewModel.viewState.isPhotoButtonEnabled)
            }
        }
        .opacity(viewModel.viewState.captureInProgress ? 0 : 1)
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
        .opacity(viewModel.viewState.captureInProgress ? 0 : 1)
        .padding(.leading)
    }
}

// MARK: - Preview

#Preview("Photo") {
    DualCameraScreen()
}

#Preview("Photo - Show Settings Button") {
    DualCameraScreen(viewModel: .init(
        showSettingsButton: true
    ))
}
