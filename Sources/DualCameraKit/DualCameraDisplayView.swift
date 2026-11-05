import SwiftUI

public struct DualCameraDisplayView: View {
    private let controller: DualCameraControlling
    private let layout: DualCameraLayout
    private let contentMode: DualCameraContentMode
    private let overlayInsets: EdgeInsets
    private let onDisplaySizeChange: (@MainActor (CGSize) -> Void)?
    private let layoutResolver = DualCameraLayoutResolver()

    /// - Parameter onDisplaySizeChange: Called with the size the cameras are laid out in, initially
    ///   and whenever it changes. Pass this size as `outputSize` when capturing so the composed photo
    ///   matches the preview. It includes any safe area the view ignores, which a `GeometryReader`
    ///   around the view does not.
    public init(
        controller: DualCameraControlling,
        layout: DualCameraLayout = .piP(
            miniCamera: .front,
            miniCameraPosition: .bottomTrailing
        ),
        contentMode: DualCameraContentMode = .aspectFill,
        overlayInsets: EdgeInsets = EdgeInsets(),
        onDisplaySizeChange: (@MainActor (CGSize) -> Void)? = nil
    ) {
        self.controller = controller
        self.layout = layout
        self.contentMode = contentMode
        self.overlayInsets = overlayInsets
        self.onDisplaySizeChange = onDisplaySizeChange
    }

    public var body: some View {
        GeometryReader { proxy in
            let resolvedLayout = layoutResolver.resolve(
                layout: layout,
                in: proxy.size,
                overlayInsets: overlayInsets
            )

            ZStack(alignment: .topLeading) {
                cameraRegion(resolvedLayout.background)

                if let overlay = resolvedLayout.overlay {
                    cameraRegion(overlay, cornerRadius: overlayCornerRadius)
                }
            }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                onDisplaySizeChange?(newSize)
            }
        }
    }

    private var overlayCornerRadius: CGFloat {
        if case .piP = layout {
            return 10
        }
        return 0
    }

    private func cameraRegion(
        _ region: DualCameraResolvedLayout.CameraRegion,
        cornerRadius: CGFloat = 0
    ) -> some View {
        DualCameraRendererView(
            renderer: controller.getRenderer(for: region.source),
            contentMode: contentMode
        )
            .frame(width: region.frame.width, height: region.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .position(x: region.frame.midX, y: region.frame.midY)
            .id(region.source)
    }
}

private struct PreviewSessionView<Content: View>: View {
    let controller: DualCameraControlling
    let content: Content

    init(controller: DualCameraControlling, @ViewBuilder content: () -> Content) {
        self.controller = controller
        self.content = content()
    }

    var body: some View {
        content
            .task {
                try? await controller.startSession()
            }
            .onDisappear {
                controller.stopSession()
            }
    }
}

@MainActor
private func previewController() -> DualCameraControlling {
    DualCameraController(streamSource: DualCameraMockCameraStreamSource())
}

#Preview("PiP - Bottom Trailing") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)
        )
    }
}

#Preview("PiP - Bottom Leading") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .piP(miniCamera: .front, miniCameraPosition: .bottomLeading)
        )
    }
}

#Preview("PiP - Top Trailing") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .piP(miniCamera: .front, miniCameraPosition: .topTrailing)
        )
    }
}

#Preview("PiP - Top Leading") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .piP(miniCamera: .front, miniCameraPosition: .topLeading)
        )
    }
}

#Preview("Stacked Vertical") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .stackedVertical
        )
    }
}

#Preview("Side by Side") {
    let controller = previewController()
    PreviewSessionView(controller: controller) {
        DualCameraDisplayView(
            controller: controller,
            layout: .sideBySide
        )
    }
}
