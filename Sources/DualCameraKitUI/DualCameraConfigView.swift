import DualCameraKit
import SwiftUI

/// Configuration sheet for selecting the dual-camera layout and photo output mode.
struct DualCameraConfigView: View {
    @Bindable private var viewModel: DualCameraViewModel

    /// Creates a configuration sheet bound to the given view model.
    init(viewModel: DualCameraViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 16) {
            layoutTypePicker
            photoOutputPicker
        }
        .sheetStyle(title: "Config")
    }

    /// Picker allowing the user to select whether only the composed photo or both composed and raw photos are saved.
    private var photoOutputPicker: some View {
        Picker(
            "Photo Output",
            selection: Binding(
                get: { viewModel.photoOutputMode },
                set: { viewModel.updatePhotoOutputMode($0) }
            )
        ) {
            ForEach(DualCameraPhotoOutputMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var layoutTypePicker: some View {
        Menu {
            ForEach(DualCameraLayout.menuItems) { menuItem in
                switch menuItem {
                case .entry(let title, let layout):
                    createMenuEntry(title: title, layout: layout)
                case .submenu(let title, let items):
                    Menu(title) {
                        ForEach(items) { subItem in
                            if case .entry(let subTitle, let subLayout) = subItem {
                                createMenuEntry(title: subTitle, layout: subLayout)
                            }
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.title)
                .foregroundColor(.white)
                .padding()
                .background(Circle().fill(Color.black.opacity(0.5)))

        }
    }

    private func createMenuEntry(title: String, layout: DualCameraLayout) -> some View {
        Group {
            Button {
                viewModel.updateLayout(layout)
            } label: {
                HStack {
                    Text(title)
                    if viewModel.cameraLayout == layout {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

#Preview {
    DualCameraConfigView(
        viewModel: DualCameraViewModel(
            dualCameraController: DualCameraController(streamSource: DualCameraMockCameraStreamSource())
        )
    )
}

#Preview("Test Pattern") {
    DualCameraConfigView(
        viewModel: DualCameraViewModel(
            dualCameraController: DualCameraController(streamSource: DualCameraMockCameraStreamSource.testPattern())
        )
    )
}
