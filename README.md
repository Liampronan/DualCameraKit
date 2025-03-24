# DualCameraKit
Current Status: Alpha release working towards 1.0. Pre-release available: [v0.2.0-alpha](https://github.com/Liampronan/DualCameraKit/releases/tag/v0.2.0-alpha).

Working: 
- rendering dual cameras in SwiftUI with various layout options (picture-in-picture, split vertical, split horizontal) 
- photo capture.
- Video capture using ReplayKit (high-def; requires one-time camera permission + ReplayKit permission each time) or our custom implementation (medium-def; requires only one-time camera permissiion) 

In-progress: de-coupling components so we can offer 3 layers of varying customizability (fully implemented drop-in screen vs. individual components); adding GPU video capture for high-def, high-UX flow (no recurrent permission requests).

## Table of Contents
- [What It Does](#what-it-does)
- [Installing DualCameraKit](#installing-dualcamerakit)
  - [In Xcode](#in-xcode)
  - [In Package.swift](#in-packageswift)
  - [Requirements](#osrequirements)
- [Running the DemoApp - Local Code Signing Setup](#running-the-demoapp---local-code-signing-setup)
- [Basic Usage](#basic-usage)
- [Customization (Raw Streams, DI, usage with UIKit, etc.)](#customization-raw-streams-di-usage-with-uikit-etc)
- [Troubleshooting](#troubleshooting)
- [Deep Dives](#deep-dives)
- [Limitations](#limitations)
- [References](#references)
- [License](#license)

# What It Does

`DualCameraKit` is an iOS library that makes simultaneous front & back camera capture simple – blending the view and the viewer in a single shot, as seen in apps like Snapchat and BeReal. 

For simple, drop-in functionality, you can use `DualCameraScreen`, a SwiftUI View that's setup with some options for different dual-camera layouts.

For deeper customizability, you can access raw front/back streams via the `DualCameraManager`,

# Example Screenshot

<img src="https://github.com/user-attachments/assets/af7af703-8033-4c07-b00c-261336ca8648" width=300 />

The above screenshot is rendered from the code below. It's the simple, drop-in style and is using one of the pre-configured layouts, `.fullScreenWithMini`. 

```swift
struct ContentView: View {
    private let dualCameraManager = DualCameraManager()
    
    var body: some View {
        DualCameraScreen(
            dualCameraManager: dualCameraManager,
            initialLayout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
        )
    }
}
```

# Installing DualCameraKit

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

- Add camera permissions to your app's `Info.plist` - `Privacy - Privacy - Camera Usage Description` 
<img src="https://github.com/user-attachments/assets/1ef0ae3e-683c-444c-9276-4684efb08e5c" width=550 />

- Live, nonsimulator device, iOS 18 for camera usage (simulator uses mocked camera). 

After installation, you can import the library in your Swift files:

```swift
import DualCameraKit
```

Now you can use `DualCameraScreen` for quick implementation or `DualCameraManager` for more customized camera control as mentioned in the README.

# Running the DemoApp - Local Code Signing Setup
To get the demo app running, you'll need to: 
1. set code signing to automatic,
2. select your development team - this dropdown appears after setting code signing to automatic 

Since this library currently requires a real device, you cannot run it on a simulator. 
<img src="https://github.com/user-attachments/assets/501070af-1466-4149-b1f1-5976fb84f37d" width="70%" /> 


# Basic Usage

# Customization (Raw Streams, usage with UIKit, etc.)

# Troubleshooting

# Deep Dives

- TODO: Explain our approach (dual streams) vs. `PiPVideoMixer` (single stream) vs `ReplayKit` (screen capture, requires user permission each time)
- TODO: Add some diagrams

# Limitations

- The library works fully on-device only! Limited, non-camera use in simulator (including previews).  
  - Why? Because the simulator doesn't have access to camera.
  - It runs in simulator & previews using mocked implementations for the cameras. The goal here is to allow you to integrate as much as possible using previews, for example, iterating on layouts. 
  - You should still test on-device as part of your full testing flow to ensure things work as you expect. 
- iOS only. iPad support is a future enhancement. Other platforms only have one camera

# References

This project was adapted from Apple's code in [`AVMultiCamPiP: Capturing from Multiple Cameras`](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras). Some significant updates here: this library ported the functionality to SwiftUI, including using a dual-stream approach vs. Apple's approach of mixing together both streams into a single CVPixelBuffer containing both camera sources.  

# License
This project is available under the [MIT License](LICENSE.md).



