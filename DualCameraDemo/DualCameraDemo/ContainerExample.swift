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
    // TODO: can/should this be dynamic?
    @State private var tabBarHeight: CGFloat = 130
    
    let vm = DualCameraViewModel(
        // TODO: cleanup this hard-coding; also move this config 
        videoRecorderMode: .cpuBased(.init(photoCaptureMode: .containerSize(.init(width: 393, height: 722))))
//        photoSaveStrategy: photoSaveStrategy
    )
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Switch between the different views based on the selected tab.
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
                            .onAppear {
                                print("proxy", proxy.size)
                            }
                        }
                        .padding(.bottom, tabBarHeight)
                    }
                    
                case .map:
                    VStack {
                        Color.teal
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // Custom tab bar at the bottom.
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
    }
    
    @ViewBuilder
    private func tabBarButton(tab: Tab, image: String, isCenter: Bool = false) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            if isCenter {
                // The center button is styled larger and in a circular shape.
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
