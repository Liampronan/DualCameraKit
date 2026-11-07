# ``DualCameraKit``

Photo-first simultaneous front and back camera capture and Metal rendering for iOS.

## Overview

`DualCameraKit` wraps `AVCaptureMultiCamSession` to run the front and back iPhone cameras simultaneously, renders both streams with Metal, and composes still images using the same layout geometry as the live preview when `outputSize` matches the preview's logical display size (note that PiP dimensions use fixed point sizes and margins rather than scaling proportionally when `outputSize` differs from the preview dimensions).

For drop-in SwiftUI screens and bundled controls, import `DualCameraKitUI` and present `DualCameraScreen` (ensure your host app's `Info.plist` includes `NSCameraUsageDescription` before presenting the screen, and `NSPhotoLibraryAddUsageDescription` if saving to the photo library). For custom UI composition, pair ``DualCameraDisplayView`` with ``DualCameraController``.

## Topics

### Session and Controller

- ``DualCameraController``
- ``DualCameraControlling``
- ``DualCameraDependencies``
- ``DualCameraSource``
- ``DualCameraError``

### Display and Layouts

- ``DualCameraDisplayView``
- ``DualCameraRendererView``
- ``CameraRenderer``
- ``MetalCameraRenderer``
- ``DualCameraLayout``
- ``DualCameraLayoutResolver``
- ``DualCameraResolvedLayout``
- ``DualCameraContentMode``

### Photo Capture and Persistence

- ``DualCameraPhotoCapturing``
- ``DualCameraPhotoCapturer``
- ``DualCameraMediaSaveStrategy``
- ``DualCameraPhotoSaveStrategy``
- ``MediaLibraryService``
- ``MediaLibraryError``

### Camera Streams and Simulator Fixtures

- ``DualCameraCameraStreamSourcing``
- ``DualCameraCameraStreamSource``
- ``DualCameraMockCameraStreamSource``
- ``DualCameraTestPattern``
- ``PixelBufferWrapper``
- ``DualCameraFramePair``

### Camera Controls and Diagnostics

- ``DualCameraCameraCapabilities``
- ``DualCameraZoomCapability``
- ``DualCameraCameraControl``
- ``DualCameraCameraControlResult``
- ``DualCameraDiagnostics``
- ``DualCameraDiagnosticEvent``
- ``DualCameraDiagnosticEventKind``
- ``DualCameraDiagnosticEventContext``
