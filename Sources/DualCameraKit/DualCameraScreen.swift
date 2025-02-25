import SwiftUI

public struct DualCameraScreen: View {
    @State private var errorMessage: String?
    private let dualCameraManager: DualCameraManager
    private let layout: CameraLayout
    private var frontCameraSize: CGSize = CGSize(width: 150, height: 200)
    private var cornerRadius: CGFloat = 10
    private var padding: CGFloat = 16

    public init(
        dualCameraManager: DualCameraManager,
        initialLayout: CameraLayout = CameraLayout.fullScreenWithMini(
            miniCamera: .front, miniCameraPosition: .bottomTrailing
        )
    ) {
        self.layout = initialLayout
        self.dualCameraManager = dualCameraManager
    }

    public var body: some View {
        ZStack {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                cameraLayoutView
            }
        }
        .task {
            // TODO: better error handling
            try? await dualCameraManager.startSession()
        }
    }

    @ViewBuilder
    private var cameraLayoutView: some View {
        switch layout {
        case .sideBySide:
            HStack {
                SingleCameraStreamView(pixelBufferWrapperStream: dualCameraManager.backCameraStream)
                    .aspectRatio(contentMode: .fit)
                SingleCameraStreamView(pixelBufferWrapperStream: dualCameraManager.backCameraStream)
                    .aspectRatio(contentMode: .fit)
            }
            .edgesIgnoringSafeArea(.all)

        case .stackedVertical:
            VStack {
                SingleCameraStreamView(pixelBufferWrapperStream: dualCameraManager.backCameraStream)
                    .aspectRatio(contentMode: .fit)
                SingleCameraStreamView(pixelBufferWrapperStream: dualCameraManager.frontCameraStream)
                    .aspectRatio(contentMode: .fit)
            }
            .edgesIgnoringSafeArea(.all)

        case .fullScreenWithMini(let miniCamera, let miniCameraPosition):
            ZStack {
                SingleCameraStreamView(pixelBufferWrapperStream: miniCamera == .front ? dualCameraManager.backCameraStream : dualCameraManager.frontCameraStream)
                    .edgesIgnoringSafeArea(.all)

                SingleCameraStreamView(pixelBufferWrapperStream: miniCamera == .front ? dualCameraManager.frontCameraStream : dualCameraManager.backCameraStream)
                    .frame(width: frontCameraSize.width, height: frontCameraSize.height)
                    .cornerRadius(cornerRadius)
                    .positioned(in: miniCameraPosition, size: frontCameraSize, padding: padding)
            }
        }
    }
}

/// Defines different layouts for dual-camera display
public enum CameraLayout: Equatable, Hashable {
    case sideBySide
    case stackedVertical
    case fullScreenWithMini(miniCamera: MiniCamera, miniCameraPosition: MiniCameraPosition)

    public enum MiniCamera: CaseIterable, Equatable, Hashable {
        case front, back
    }
    
    /// Defines positions where the mini camera can be placed.
    public enum MiniCameraPosition: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// Returns the appropriate offset for the given position
        func offset(for size: CGSize, padding: CGFloat) -> CGSize {
            switch self {
            case .topLeading:
                return CGSize(width: -size.width / 2 - padding, height: -size.height / 2 - padding)
            case .topTrailing:
                return CGSize(width: size.width / 2 + padding, height: -size.height / 2 - padding)
            case .bottomLeading:
                return CGSize(width: -size.width / 2 - padding, height: size.height / 2 + padding)
            case .bottomTrailing:
                return CGSize(width: size.width / 2 + padding, height: size.height / 2 + padding)
            }
        }

        /// Returns the appropriate alignment for SwiftUI `.position`
        func alignment() -> Alignment {
            switch self {
            case .topLeading:
                return .topLeading
            case .topTrailing:
                return .topTrailing
            case .bottomLeading:
                return .bottomLeading
            case .bottomTrailing:
                return .bottomTrailing
            }
        }
    }
}

// TODO: figure out preview strategy here - mock streams
//#Preview {
//    VStack {
//        DualCameraView(initialLayout: .sideBySide)
//        DualCameraView(initialLayout: .stackedVertical)
//        DualCameraView(initialLayout: .fullScreenWithMini(miniCamera: .front))
//    }
//}
