import DualCameraKit
import SwiftUI

struct ContainerExample: View {
    var body: some View {
        AppTabView()
    }
}

enum Tab {
    case feed, camera, map
}

@Observable
final class CaptureReviewState {
    enum PreviewPhase: Equatable {
        case hidden
        case showing(UIImage)
    }
    var previewPhase = PreviewPhase.hidden
    
    func showPreview(_ image: UIImage) {
        withAnimation {
            previewPhase = .showing(image)
        }
    }
    
    func reset() {
        withAnimation {
            previewPhase = .hidden
        }
        
    }
}

private struct AppTabView: View {
    @State private var selectedTab: Tab = .camera
    @State private var captureReviewState = CaptureReviewState()
    private var vm: DualCameraViewModel

    init() {
        vm = DualCameraViewModel(
            captureScope: .container,
            includeVideoRecording: false,
            saveToLibrary: false
        )
    }
    
    var body: some View {
        ZStack {
            VStack {
                switch selectedTab {
                case .feed:
                    feedMock
                case .camera:
                    cameraCapture
                case .map:
                    mapMock
                }
                tabBar
                .edgesIgnoringSafeArea(.all)
            }
                
            switch captureReviewState.previewPhase {
            case .hidden:
                EmptyView()
            case .showing(let image):
                CapturePreviewOverlay(
                    image: image,
                    onDismiss: {
                        captureReviewState.reset()
                    },
                    onConfirm: {
                        captureReviewState.reset()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(.primary)
        .onChange(of: vm.capturedPhoto) { oldValue, newValue in
            if let image = newValue {
                captureReviewState.showPreview(image)
            }
        }
    }
    
    private var cameraCapture: some View {
        DualCameraScreen(
            viewModel: vm
        )
    }
    
    private var feedMock: some View {
        VStack {
            Color(.systemMint)
        }
    }
    
    private var mapMock: some View {
        VStack {
            Color(.systemTeal)
        }
    }
    
    @ViewBuilder
    private var tabBar: some View {
        HStack {
            tabBarButton(tab: .map, image: "map.fill")
            Spacer()
            tabBarButton(tab: .camera, image: "house.fill", isCenter: true)
            Spacer()
            tabBarButton(tab: .feed, image: "bubble.left.and.bubble.right.fill")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(20)
        .shadow(radius: 5)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func tabBarButton(tab: Tab, image: String, isCenter: Bool = false) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            if isCenter {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 60, height: 60)
                        .shadow(radius: 4)
                    Image(systemName: image)
                        .font(.system(size: 24))
                        .foregroundColor(Color(.label))
                }
            } else {
                Image(systemName: image)
                    .font(.system(size: 24))
                    .foregroundColor(selectedTab == tab ? Color.accentColor : Color(.secondaryLabel))
            }
        }
    }
}

#Preview {
    AppTabView()
}
