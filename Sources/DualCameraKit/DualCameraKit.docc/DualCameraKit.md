# ``DualCameraKit``

Photo-first simultaneous front and back camera capture and Metal rendering for iOS.

## Overview

`DualCameraKit` wraps `AVCaptureMultiCamSession` to run the front and back iPhone cameras simultaneously, renders both streams with Metal, and composes still images using the same layout geometry as the live preview.

For drop-in SwiftUI screens and bundled controls, import `DualCameraKitUI` and present `DualCameraScreen`. For custom UI composition, pair ``DualCameraDisplayView`` with ``DualCameraController``.

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
