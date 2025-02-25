# What It Does

`DualCameraKit` is an iOS library that makes simultaneous front & back camera capture simple and allows for deeper customization if you're looking beyond simplicity.

For simple, drop-in functionality, you can use `DualCameraScreen`, a SwiftUI View that's setup with some options for different dual-camera layouts.

For deeper customizability, you can access raw front/back streams via the `DualCameraManager`,

# Installation

### Running the DemoApp - Local Code Signing Setup

You can either manually set the development team in Xcode OR follow the below steps to allow for an automated workflow, which is helpful for more frequent testing, CI config, etc.  

1. **Create a `LocalOverrides.xcconfig`** in the `DualCameraDemo` folder (alongside the `Base.xcconfig`).
2. Add your personal code signing details, e.g.:
   ```plaintext
   DEVELOPMENT_TEAM = ABC123XYZ
   CODE_SIGN_STYLE = Automatic
   CODE_SIGN_IDENTITY = Apple Development
   ```

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

# License
