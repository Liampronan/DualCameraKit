import DualCameraKit
import SwiftUI

struct CompositionalExample: View {
    @State private var controller = CurrentDualCameraEnvironment.dualCameraController
    @State private var layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    @State private var capturedImage: UIImage?
    @State private var alertMessage: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DualCameraDisplayView(controller: controller, layout: layout)

                VStack {
                    layoutPicker
                    Spacer()
                    captureButton(outputSize: proxy.size)
                }
                .padding()
            }
            .task {
                try? await controller.startSession()
            }
            .onDisappear {
                controller.stopSession()
            }
            .sheet(isPresented: previewBinding) {
                if let capturedImage {
                    CapturePreviewOverlay(
                        image: capturedImage,
                        onDismiss: { self.capturedImage = nil },
                        onConfirm: { self.capturedImage = nil }
                    )
                }
            }
            .alert("Capture Failed", isPresented: alertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "Unknown error")
            }
        }
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: $layout) {
            Text("PiP").tag(DualCameraLayout.piP(miniCamera: .front, miniCameraPosition: .bottomTrailing))
            Text("Split").tag(DualCameraLayout.sideBySide)
            Text("Stack").tag(DualCameraLayout.stackedVertical)
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .padding()
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
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
