# What It Does

`DualCameraKit` is an iOS library that makes simultaneous front & back camera capture simple and allows for deeper customization if you're looking beyond simplicity.

For simple, drop-in functionality, you can use `DualCameraScreen`, a SwiftUI View that's setup with some options for different dual-camera layouts.

For deeper customizability, you can access raw front/back streams via the `DualCameraManager`,

# Installation

# Basic Usage

# Customization (Raw Streams, DI, usage with UIKit, etc.)s\

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
