import DualCameraKit
import SwiftUI
import UIKit

public struct DualCameraScreen: View {
    private static let screenCoordinateSpaceName = "DualCameraScreenCoordinateSpace"

    @Environment(\.displayScale) private var displayScale
    @State private var viewModel: DualCameraViewModel
    @State private var cameraDisplaySize: CGSize = .zero
    private let shutter: (ShutterContext) -> AnyView
    private let customOverlay: ((DualCameraViewModel) -> AnyView)

    @MainActor
    public init(
        viewModel: DualCameraViewModel? = nil,
        @ViewBuilder customOverlay: @escaping (DualCameraViewModel) -> some View = { _ in EmptyView() }
    ) {
        let resolvedViewModel = viewModel ?? .default()
        _viewModel = State(initialValue: resolvedViewModel)
        self.shutter = { AnyView(DualCameraDefaultShutterButton(context: $0)) }
        self.customOverlay = { AnyView(customOverlay($0)) }
    }

    @MainActor
    public init(
        viewModel: DualCameraViewModel? = nil,
        @ViewBuilder shutter: @escaping (ShutterContext) -> some View,
        @ViewBuilder customOverlay: @escaping (DualCameraViewModel) -> some View = { _ in EmptyView() }
    ) {
        let resolvedViewModel = viewModel ?? .default()
        _viewModel = State(initialValue: resolvedViewModel)
        self.shutter = { AnyView(shutter($0)) }
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
                overlayInsets: viewModel.overlayInsets,
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
        .coordinateSpace(name: Self.screenCoordinateSpaceName)
        .onAppear {
            viewModel.onAppear(containerSize: cameraDisplaySize, displayScale: displayScale)
        }
        .onChange(of: displayScale, initial: true) { _, newScale in
            viewModel.displayScaleChanged(newScale)
        }
        .onChange(of: viewModel.showsShutterButton, initial: true) { _, showsShutter in
            if !showsShutter {
                viewModel.shutterFrameChanged(.zero)
            }
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
                .environment(\.dualCameraShutterHeight, viewModel.shutterHeight)
                .environment(\.dualCameraShutterFrame, viewModel.shutterFrame)
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
        if viewModel.showsShutterButton {
            VStack(spacing: 16) {
                HStack(spacing: 32) {
                    shutter(viewModel.shutterContext)
                        .accessibilityAddTraits(.isButton)
                        .disabled(!viewModel.isPhotoButtonEnabled)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(
                            of: proxy.frame(in: .named(Self.screenCoordinateSpaceName)),
                            initial: true
                        ) { _, newFrame in
                            viewModel.shutterFrameChanged(newFrame)
                        }
                }
                ShutterAccessibilityMetadataView(
                    isEnabled: viewModel.isPhotoButtonEnabled,
                    isCapturing: viewModel.isCapturing,
                    label: nil
                )
            }
            .opacity(viewModel.isCapturing ? 0 : 1)
            .accessibilityHidden(viewModel.isCapturing)
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
