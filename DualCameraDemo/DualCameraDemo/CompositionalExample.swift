import DualCameraKit
import SwiftUI

struct CompositionalExample: View {
    private enum LayoutMode: String, CaseIterable, Identifiable {
        case piP = "PiP"
        case split = "Split"
        case stack = "Stack"

        var id: String { rawValue }
    }

    @State private var controller = CurrentDualCameraEnvironment.dualCameraController
    @State private var layoutMode = LayoutMode.piP
    @State private var miniCameraPosition = DualCameraLayout.MiniCameraPosition.bottomTrailing
    @State private var capturedImage: UIImage?
    @State private var alertMessage: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DualCameraDisplayView(
                    controller: controller,
                    layout: layout,
                    overlayInsets: cameraOverlayInsets(for: proxy)
                )
                .ignoresSafeArea()
                .animation(layoutAnimation, value: layout)

                VStack(spacing: 0) {
                    compositionControls
                    Spacer()
                    captureButton(outputSize: proxy.size)
                }
                .padding(.horizontal, 16)
                .padding(.top, controlsTopPadding(for: proxy))
                .padding(.bottom, controlsBottomPadding(for: proxy))
            }
            .task {
                try? await controller.startSession()
            }
            .onDisappear {
                controller.stopSession()
            }
            .fullScreenCover(isPresented: previewBinding) {
                if let capturedImage {
                    CapturePreviewOverlay(
                        image: capturedImage,
                        onDismiss: { self.capturedImage = nil },
                        onConfirm: { self.capturedImage = nil }
                    )
                    .ignoresSafeArea()
                }
            }
            .alert("Capture Failed", isPresented: alertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "Unknown error")
            }
        }
    }

    private var layoutAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var layout: DualCameraLayout {
        switch layoutMode {
        case .piP:
            return .piP(miniCamera: .front, miniCameraPosition: miniCameraPosition)
        case .split:
            return .sideBySide
        case .stack:
            return .stackedVertical
        }
    }

    private var compositionControls: some View {
        VStack(spacing: 10) {
            layoutPicker
            if layoutMode == .piP {
                pipPositionPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .animation(layoutAnimation, value: layoutMode)
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: layoutSelection) {
            ForEach(LayoutMode.allCases) { layoutMode in
                Text(layoutMode.rawValue).tag(layoutMode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var pipPositionPicker: some View {
        Picker("PiP Position", selection: pipPositionSelection) {
            Image(systemName: "arrow.up.left")
                .tag(DualCameraLayout.MiniCameraPosition.topLeading)
                .accessibilityLabel("Top Left")
            Image(systemName: "arrow.up.right")
                .tag(DualCameraLayout.MiniCameraPosition.topTrailing)
                .accessibilityLabel("Top Right")
            Image(systemName: "arrow.down.left")
                .tag(DualCameraLayout.MiniCameraPosition.bottomLeading)
                .accessibilityLabel("Bottom Left")
            Image(systemName: "arrow.down.right")
                .tag(DualCameraLayout.MiniCameraPosition.bottomTrailing)
                .accessibilityLabel("Bottom Right")
        }
        .pickerStyle(.segmented)
    }

    private func captureButton(outputSize: CGSize) -> some View {
        Button {
            Task {
                do {
                    capturedImage = try await controller.capturePhoto(layout: layout, outputSize: outputSize)
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var layoutSelection: Binding<LayoutMode> {
        Binding(
            get: { layoutMode },
            set: { newValue in
                withAnimation(layoutAnimation) {
                    layoutMode = newValue
                }
            }
        )
    }

    private var pipPositionSelection: Binding<DualCameraLayout.MiniCameraPosition> {
        Binding(
            get: { miniCameraPosition },
            set: { newValue in
                withAnimation(layoutAnimation) {
                    miniCameraPosition = newValue
                }
            }
        )
    }

    private func cameraOverlayInsets(for proxy: GeometryProxy) -> EdgeInsets {
        EdgeInsets(
            top: controlsTopPadding(for: proxy) + 116,
            leading: 8,
            bottom: controlsBottomPadding(for: proxy) + 78,
            trailing: 8
        )
    }

    private func controlsTopPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.top + 72, 118)
    }

    private func controlsBottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.bottom + 24, 34)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private var previewBinding: Binding<Bool> {
        Binding(
            get: { capturedImage != nil },
            set: { if !$0 { capturedImage = nil } }
        )
    }
}
