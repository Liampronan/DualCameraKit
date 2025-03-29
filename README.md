# DualCameraKit


![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen)
![iOS](https://img.shields.io/badge/iOS-17+-lightgrey?logo=apple)
![WIP](https://img.shields.io/badge/status-WIP-yellow)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)


Simultaneous front & back iOS camera capture made simple.

<table>
<tr>
  <td align="center"><img src="./DocumentationAssets/Photo_Capture.png" width="250"/><br><b>Photo Capture</b></td>
  <td align="center"><img src="./DocumentationAssets/Video_Recording_ReplayKit.gif" width="250"/><br><b>Video Capture</b></td>
</tr>
</table>

# Status Overview

**Current Status**: Alpha release working towards 1.0

**Pre-release available**: [v0.3.0-alpha](https://github.com/Liampronan/DualCameraKit/releases/tag/v0.3.0-alpha).

**Legend**: ✅ = Implemented | 🚧 = In Progress

| Category                | Status | Description                                                                                                                                      |
| ----------------------- | :----: | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| 📱 **UI Components**    |   ✅   | Rendering dual cameras in SwiftUI with various layout options:<br>• Picture-in-picture<br>• Split vertical<br>• Split horizontal                 |
| 📸 **Photo Capture**    |   ✅   | Implemented via screen capture                                                                                                                   |
| 🎬 **Video Capture**    | v1 ✅  | **ReplayKit Mode**: High-def output (requires permission each time)<br>**CPU-based Mode**: Medium-def output (one-time permission only)          |
| 🧩 **Architecture**     |   🚧   | In progress: De-coupling components to offer 3 layers of customizability:<br>• Drop-in screen<br>• Compositional views<br>• Low-level components |
| 🔥 **GPU Acceleration** |   🚧   | Up Next: Adding GPU video capture for high-def recording without<br>recurrent permission requests                                                |
| 🎤 **Audio**            |   🚧   | Future: Adding audio capture support for video recording.                                                                                        |

# Table of Contents

- [What It Does](#what-it-does)
- [Requirements](#osrequirements)
- [Installing](#installing)
  - [In Xcode](#in-xcode)
  - [In Package.swift](#in-packageswift)
- [Running the Demo App](#running-the-demo-app-local-code-signing-setup)
- [Basic Usage](#basic-usage)
- [Customization](#customization)
  - [Camera Layout Types](#camera-layout-types)
  - [Video Recording Modes](#video-recording-modes)
- [Troubleshooting](#troubleshooting)
- [Deep Dives](#deep-dives)
- [Limitations](#limitations)
- [API Reference](#api-reference)
- [References](#references)
- [License](#license)

# What It Does

`DualCameraKit` is an iOS library that makes simultaneous front & back camera capture simple – combining the view and the viewer in a single shot, as seen in apps like Snapchat and BeReal.

For simple, drop-in functionality, you can use `DualCameraScreen`, a SwiftUI View with buttons for photo capture, video recording, and toggling through the different dual-camera layouts and recording modes.

For deeper customizability, you can access the lower-level components that `DualCameraScreen` is built on

# Installing

Since `DualCameraKit` is published using Swift Package Manager, you can install it by following these steps:

## In Xcode:

1. Go to **File > Add Packages...**
2. In the search bar, paste this [repository URL](https://github.com/Liampronan/DualCameraKit).
3. Select the version rule (e.g., "Up to Next Major" is recommended for most cases)
4. Click **Add Package**
5. Select the `DualCameraKit` library product
6. Click **Add Package** to complete the installation

## In Package.swift:

If you're developing a Swift package that depends on `DualCameraKit`, add it to your package dependencies:

```swift
dependencies: [
    .package(url: "https://url-to-dualcamerakit-repo.git", from: $VERSION_STRING_HERE$)
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["DualCameraKit"]
    )
]
```

## OS/Requirements:

- Add camera permissions to your app's `Info.plist` - `Privacy - Camera Usage Description`
  <img src="https://github.com/user-attachments/assets/1ef0ae3e-683c-444c-9276-4684efb08e5c" width=550 />

- Live, nonsimulator device, iOS 17+ for camera usage (simulator uses mocked camera).

After installation, you can import the library in your Swift files:

```swift
import DualCameraKit
```

# Running the Demo App: Local Code Signing Setup

To get the demo app running, you'll need to:

1. set code signing to automatic,
2. select your development team - this dropdown appears after setting code signing to automatic

Since this library currently requires a real device, you cannot run it on a simulator.
<img src="https://github.com/user-attachments/assets/501070af-1466-4149-b1f1-5976fb84f37d" width="70%" />

# Overview: the three ways to use this library

Three are three different sets of components this library exposes, ranging from higher-level (drop-in, less customizable) to lower-level (more customizable). Each is built on top of the next lower level.

1. ✅ `DualCameraScreen`

- drop-in, least customizable.
- a full-screen SwiftUI view which includes buttons for photo capture, video recording, and toggling through the different dual-camera layouts and recording modes.

2. 🚧 `DualCameraDisplayView` and `DualCameraController`

- medium customization - useful for using pre-configured dual camera layouts while customizing the control UI and post-capture behavior.
- the `DualCameraDisplayView` renders streams managed by the `DualCameraController`
- you're responsible for wiring up UI for photo capture, video recording management, and layout config.

3. 🚧 Raw Components

- full customization - useful for uncharted territory e.g., you need to manipulate camera streams before they are rendered.

# Basic Usage

## `DualCameraScreen` - drop-in, full-screen component

The simplest way to use DualCameraKit is with the default configuration:

```swift
struct ContentView: View {
    var body: some View {
        DualCameraScreen()
    }
}
```

## `DualCameraScreen` - Customization

You can customize the screen by providing your own `DualCameraViewModel`

```swift
// Custom initialization with specific layout
let customViewModel = DualCameraViewModel(
    dualCameraController: DualCameraController(),
    layout: .sideBySide,
    videoRecorderMode: .replayKit(),
    videoSaveStrategy: .custom { url in
        // Custom video handling
        print("Video saved to: \(url)")
    },
    photoSaveStrategy: .custom { image in
        // Custom photo handling
        saveToCloudService(image)
    }
)

struct ContentView: View {
    var body: some View {
        DualCameraScreen(viewModel: customViewModel)
    }
}
```

## `DualCameraScreen` - Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `viewModel` | `DualCameraViewModel` | `.default()` | Provides complete configuration for the camera screen including layout, video recording options, and media saving strategies. |

## `DualCameraViewModel` Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dualCameraController` | `DualCameraControlling` | Device-specific controller | Core camera controller. Uses `DualCameraMockController` on simulator and `DualCameraController` on device. |
| `layout` | `DualCameraLayout` | `.piP(miniCamera: .front, miniCameraPosition: .bottomTrailing)` | Determines how cameras are displayed (picture-in-picture, side-by-side, or stacked). |
| `videoRecorderMode` | `DualCameraVideoRecordingMode` | `.cpuBased(.init(photoCaptureMode: .fullScreen))` | Configures video recording strategy and quality. |
| `videoSaveStrategy` | `VideoSaveStrategy` | `.videoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService)` | Strategy for saving recorded videos. |
| `photoSaveStrategy` | `PhotoSaveStrategy` | `.photoLibrary(service: CurrentDualCameraEnvironment.mediaLibraryService)` | Strategy for saving captured photos. |

> Note on Default Media Handling: By default, all photos and videos are saved to the device's photo library. This requires the user to grant permission when first capturing media. The default implementation handles permission requests, file cleanup, and provides success feedback. When using custom strategies, you'll need to implement these aspects yourself if needed.

## Testing Support

For testing, you can use the mock implementations:

```swift
let testViewModel = DualCameraViewModel(
    dualCameraController: DualCameraMockController(),
    videoSaveStrategy: .custom { _ in },
    photoSaveStrategy: .custom { _ in }
)
```

# Customization

## Camera Layout Types

```swift
public enum DualCameraLayout {
    case sideBySide
    case stackedVertical
    case piP(miniCamera: DualCameraSource, miniCameraPosition: MiniCameraPosition)
}
```

> Note: these screenshots are using colors to mock the front (purple) and back (yellow) cameras – this is how we're mocking things in the simulator because it doesn't have a hardware camera.

### `.piP(miniCamera:, miniCameraPosition:)`

|                                                                                                       |                                                                                                         |
| :---------------------------------------------------------------------------------------------------: | :-----------------------------------------------------------------------------------------------------: |
|    <img src="./DocumentationAssets/Layout_PiP_Top_Leading.png" width="250" /><br>**`.topLeading`**    |    <img src="./DocumentationAssets/Layout_PiP_Top_Trailing.png" width="250" /><br>**`.topTrailing`**    |
| <img src="./DocumentationAssets/Layout_PiP_Bottom_Leading.png" width="250" /><br>**`.bottomLeading`** | <img src="./DocumentationAssets/Layout_PiP_Bottom_Trailing.png" width="250" /><br>**`.bottomTrailing`** |

### `.stackedVertical`

<img src="./DocumentationAssets/Layout_Stacked_Vertical.png" width=250 />

### `.sideBySide`

<img src="./DocumentationAssets/Layout_Side_by_Side.png" width=250 />

## Video Recording Modes

- This library offers several implementations of `DualCameraVideoRecorderType` that offer various methods of recording video.
- You can choose which type you'd like by invoking `DualCameraControlling.startVideoRecording(recorderType:)`

| Type                    | Implementation Status | Quality |                   Description                   |      Core Technology       |          Permissions Required           |                       Layout Dependence                       |
| ----------------------- | :-------------------: | :-----: | :---------------------------------------------: | :------------------------: | :-------------------------------------: | :-----------------------------------------------------------: |
| `.cpuBased`             |          ✅           | Medium  |          Takes continuous screenshots           | `DualCameraPhotoCapturing` |            Camera (one-time)            |                 Captures screen layout as-is                  |
| `.replayKit`            |          ✅           |  High   |           System screen recording API           |         ReplayKit          | Camera (one-time) + ReplayKit (per-use) |                 Captures screen layout as-is                  |
| `.gpuBasedUncomposited` |          🚧           |  High   |              Direct Metal capture               |   Metal/GPU acceleration   |            Camera (one-time)            |  Produces separate video streams (manual composition needed)  |
| `.gpuBasedComposited`   |          🚧           |  High   | Direct Metal capture with automatic composition |   Metal/GPU acceleration   |            Camera (one-time)            | Automatically composes videos according to `DualCameraLayout` |

# Troubleshooting

# Deep Dives

- 🚧 Explain our different approaches (dual streams) vs. `PiPVideoMixer` (single stream) vs `ReplayKit` (screen capture, requires user permission each time)
- 🚧 Add some diagrams

# Limitations

- The library works fully on-device only! Limited, non-camera use in simulator (including previews).
  - Why? Because the simulator doesn't have access to camera.
  - It runs in simulator & previews using mocked implementations for the cameras. The goal here is to allow you to integrate as much as possible using previews, for example, iterating on layouts.
  - You should still test on-device as part of your full testing flow to ensure things work as you expect.
- iOS only. iPad support is a future enhancement. Other platforms only have one camera

# API Reference
🚧

# References

Part of this project was adapted from Apple's code in [`AVMultiCamPiP: Capturing from Multiple Cameras`](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras). Some significant updates here: this library ports the functionality to SwiftUI, including using a dual-stream approach with multiple types of video recorders vs. Apple's approach of mixing together both streams into a single CVPixelBuffer containing both camera sources.

# License

This project is available under the [MIT License](LICENSE.md).
