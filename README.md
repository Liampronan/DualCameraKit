# DualCameraKit
Current Status: Alpha release working towards 1.0.

Working: rendering dual cameras in SwiftUI with various layout options. 

In-progress: user can record & export dual cameras feed - currently we can only view the dual camera steams. 

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

`DualCameraKit` is an iOS library that makes simultaneous front & back camera capture simple – as seen in apps like Snapchat and BeReal.

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

- Live, nonsimulator device, iOS 18. 

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

# Customization (Raw Streams, DI, usage with UIKit, etc.)

# Troubleshooting

# Deep Dives

- TODO: Explain our approach (dual streams) vs. `PiPVideoMixer` (single stream)
- TODO: Add some diagrams

# Limitations

- BUG: demo app - first launch post-permission flow. does it render?
- TODO: add video saving
- iOS only. iPad support is a future enhancement, other platforms only have one camera
- This library works on-device only! Simulator (including previews) doesn't have access to camera.
  - There's a TODO for simulator support via mocking

# References

This project was adapted from Apple's code in [`AVMultiCamPiP: Capturing from Multiple Cameras`](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras). Some significant updates here: this library ported the functionality to SwiftUI, including using a dual-stream approach vs. Apple's approach of mixing together both streams into a single CVPixelBuffer containing both camera sources.  

# License
This project is available under the [MIT License](LICENSE.md).



