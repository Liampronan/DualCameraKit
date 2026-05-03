import DualCameraKit
import SwiftUI

struct DualCameraConfigView: View {
    @Bindable private var viewModel: DualCameraViewModel

    init(viewModel: DualCameraViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            layoutTypePicker
        }
        .sheetStyle(title: "Config")
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
