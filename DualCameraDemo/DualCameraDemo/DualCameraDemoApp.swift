import DualCameraKit
import DualCameraKitUI
import Observation
import SwiftUI

@main
struct DualCameraDemoApp: App {
    enum DemoDisplayType: String, CaseIterable, Identifiable {
        case dropIn = "Drop-in"
        case container = "Container"
        case compositional = "Compositional"

        var id: String { rawValue }
    }

    @State private var demoType = DemoDisplayType.container

    var body: some Scene {
        WindowGroup {
            ZStack {
                selectedDemo
                    .id(demoType)
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .top) {
                demoPicker
            }
            .animation(.easeInOut(duration: 0.18), value: demoType)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var selectedDemo: some View {
        switch demoType {
        case .dropIn:
            DualCameraScreen()
        case .container:
            ContainerExample()
        case .compositional:
            CompositionalExample()
        }
    }

    private var demoPicker: some View {
        Picker("Demo", selection: demoSelection) {
            ForEach(DemoDisplayType.allCases) { demo in
                Text(demo.rawValue).tag(demo)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private var demoSelection: Binding<DemoDisplayType> {
        Binding(
            get: { demoType },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    demoType = newValue
                }
            }
        )
    }
}
