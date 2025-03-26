//
//  CameraConfigView.swift
//  DualCameraKit
//
//  Created by Liam Ronan on 3/25/25.
//


import DualCameraKit
import SwiftUI

struct CameraConfigView: View {
    @Bindable private var viewModel: DualCameraViewModel
    
    init(viewModel: DualCameraViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack {
            layoutTypePicker
            recorderTypePicker
        }
        .sheetStyle(title: "Config")
    }
    
    @ViewBuilder
    private var layoutTypePicker: some View {
        Menu {
            ForEach(CameraLayout.menuItems) { menuItem in
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
    
    private func createMenuEntry(title: String, layout: CameraLayout) -> some View {
        Group {
            
            Button {
                viewModel.updateLayout(layout)
            } label: {
                HStack {
                    Text(title)
                    if viewModel.configuration.layout == layout {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var recorderTypePicker: some View {
        VStack {
            Menu {
                ForEach(DualCameraVideoRecorderType.allCases) { recorderType in
                    Button {
                        viewModel.toggleRecorderType()
                    } label: {
                        HStack {
                            Text(recorderType.displayName)
                            if viewModel.videoRecorderType == recorderType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Recorder: \(viewModel.videoRecorderType.displayName)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    CameraConfigView(viewModel: DualCameraViewModel(dualCameraController: DualCameraMockController()))
}
