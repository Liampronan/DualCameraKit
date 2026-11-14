import CoreVideo
import DualCameraEmojiKit
import DualCameraEmojiKitUI
import DualCameraKit
import DualCameraKitUI
import SwiftUI
import UIKit

struct EmojiFilterExample: View {
    @State private var plugin: EmojiFaceFilterPlugin
    @State private var viewModel: DualCameraViewModel
    @State private var reviewPhoto: UIImage?

    @MainActor
    init() {
        let plugin = Self.makeDefaultPlugin()
        let controller = Self.makeDefaultController(frameProcessor: plugin.processor)
        let viewModel = DualCameraViewModel(
            dualCameraController: controller,
            layout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
            overlayInsets: EdgeInsets(top: 112, leading: 12, bottom: 24, trailing: 12),
            photoSaveStrategy: .custom { _ in },
            showSettingsButton: true
        )
        _plugin = State(initialValue: plugin)
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        DualCameraScreen(viewModel: viewModel) { activeViewModel in
            EmojiFilterToolbar(plugin: plugin) {
                activeViewModel.controller.setFrameProcessor(plugin.processor)
            }
            .padding(.top, 56)
        }
        .fullScreenCover(isPresented: reviewBinding) {
            if let reviewPhoto {
                CapturePreviewOverlay(
                    image: reviewPhoto,
                    onDismiss: { self.reviewPhoto = nil },
                    onConfirm: { self.reviewPhoto = nil }
                )
                .presentationBackground(.black)
            }
        }
        .onChange(of: viewModel.capturedPhoto) { _, newValue in
            if let newValue {
                reviewPhoto = newValue
            }
        }
    }

    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { reviewPhoto != nil },
            set: { if !$0 { reviewPhoto = nil } }
        )
    }

    @MainActor
    private static func makeDefaultPlugin() -> EmojiFaceFilterPlugin {
        let configuration = EmojiFaceFilterConfiguration(
            isEnabled: true,
            targetSources: [.front, .back],
            assignment: .single("😎"),
            scaleMultiplier: 1.4,
            tracksHeadRoll: true,
            redactRawCaptures: true
        )
        #if targetEnvironment(simulator)
        return EmojiFaceFilterPlugin(
            configuration: configuration,
            faceDetector: SimulatorSyntheticFaceDetector()
        )
        #else
        return EmojiFaceFilterPlugin(configuration: configuration)
        #endif
    }

    @MainActor
    private static func makeDefaultController(
        frameProcessor: any DualCameraFrameProcessing
    ) -> DualCameraControlling {
        #if targetEnvironment(simulator)
        let streamSource = DualCameraMockCameraStreamSource(
            front: DualCameraTestPattern.image(for: .front),
            back: DualCameraTestPattern.image(for: .back)
        )
        return DualCameraController(
            streamSource: streamSource,
            frameProcessor: frameProcessor
        )
        #else
        return DualCameraController(frameProcessor: frameProcessor)
        #endif
    }
}

#if targetEnvironment(simulator)
private struct SimulatorSyntheticFaceDetector: FaceDetectionProviding {
    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [DetectedFace] {
        [
            DetectedFace(
                boundingBox: CGRect(x: 0.34, y: 0.36, width: 0.32, height: 0.32),
                rollAngleRadians: -0.10
            )
        ]
    }
}
#endif

#Preview("Emoji Filter Example") {
    EmojiFilterExample()
}
