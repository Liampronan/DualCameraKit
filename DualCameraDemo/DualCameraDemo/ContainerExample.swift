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

let photoSaveStrategy: DualCameraPhotoSaveStrategy = .custom { image in
    print("captured", image)
}

private struct AppTabView: View {
    @State private var selectedTab: Tab = .camera
    
    let vm = DualCameraViewModel(
        captureScope: .container
    )
    
    var body: some View {
        VStack {
            Group {
                switch selectedTab {
                case .feed:
                    VStack {
                        Color.mint
                    }
                case .camera:
                    ZStack {
                        GeometryReader { proxy in
                            DualCameraScreen(
                                viewModel: vm
                            )
                            .onChange(of: proxy.size, initial: true) { _, newSize in
                                vm.containerSizeChanged(newSize)
                            }
                        }
                    }
                case .map:
                    VStack {
                        Color.teal
                    }
                }
            }
            tabBar
            .edgesIgnoringSafeArea(.all)
        }
    }
    
    @ViewBuilder
    private var tabBar: some View {
        HStack {
            tabBarButton(tab: .feed, image: "house.fill")
            Spacer()
            tabBarButton(tab: .camera, image: "camera.fill", isCenter: true)
            Spacer()
            tabBarButton(tab: .map, image: "bubble.left.and.bubble.right.fill")
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
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                        .shadow(radius: 4)
                    Image(systemName: image)
                        .font(.system(size: 24))
                        .foregroundColor(.black)
                }
            } else {
                Image(systemName: image)
                    .font(.system(size: 24))
                    .foregroundColor(selectedTab == tab ? .blue : .gray)
            }
        }
    }
}

#Preview {
    AppTabView()
}
