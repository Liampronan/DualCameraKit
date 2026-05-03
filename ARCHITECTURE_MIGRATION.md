# Architecture Migration: Screenshot → Stream Composition

## Goal
Move from screenshot-based capture to native camera stream composition for:
- Higher quality output (native camera resolution)
- Better performance (GPU-accelerated)
- Production-ready implementation

---

## Phase 1: Photo Capture from Streams

### Current Flow
```
Camera → Metal Renderer → SwiftUI Display → Screenshot → Image
```

### Target Flow
```
Front Camera → Capture Frame →
                               ↓
                         Composition Engine (Metal) → High-Res Image
                               ↑
Back Camera → Capture Frame →
```

### Implementation Tasks

#### 1.1 Add Frame Capture to CameraRenderer
**File**: `Sources/DualCameraKit/CameraRenderer.swift`

```swift
protocol CameraRenderer {
    // Existing
    func update(with buffer: CVPixelBuffer)
    func captureCurrentFrame() async throws -> UIImage

    // NEW: Get raw buffer instead of UIImage
    func captureCurrentBuffer() async throws -> CVPixelBuffer
}
```

#### 1.2 Create Stream-based Photo Composition Engine
**New File**: `Sources/DualCameraKit/DualCameraStreamPhotoCapturer.swift`

```swift
/// Captures and composes photos from independent camera streams
public class DualCameraStreamPhotoCapturer: DualCameraPhotoCapturing {

    /// Capture synchronized frames from both cameras and compose them
    func captureComposedPhoto(
        frontRenderer: CameraRenderer,
        backRenderer: CameraRenderer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> UIImage {
        // 1. Capture raw buffers from both cameras (native resolution)
        let frontBuffer = try await frontRenderer.captureCurrentBuffer()
        let backBuffer = try await backRenderer.captureCurrentBuffer()

        // 2. Compose using Metal/Core Image based on layout
        let composedBuffer = try await compose(
            front: frontBuffer,
            back: backBuffer,
            layout: layout,
            outputSize: outputSize
        )

        // 3. Convert to UIImage
        return try createImage(from: composedBuffer)
    }

    private func compose(
        front: CVPixelBuffer,
        back: CVPixelBuffer,
        layout: DualCameraLayout,
        outputSize: CGSize
    ) async throws -> CVPixelBuffer {
        // Use Metal shaders or Core Image to compose frames
        switch layout {
        case .piP(let miniCamera, let position):
            return try composePictureInPicture(
                primary: miniCamera == .front ? back : front,
                mini: miniCamera == .front ? front : back,
                position: position,
                outputSize: outputSize
            )
        case .sideBySide:
            return try composeSideBySide(front: front, back: back, outputSize: outputSize)
        // ... other layouts
        }
    }
}
```

#### 1.3 Composition Engine (Metal or Core Image)

**Option A: Core Image** (Easier, good quality)
```swift
private func composePictureInPicture(
    primary: CVPixelBuffer,
    mini: CVPixelBuffer,
    position: MiniCameraPosition,
    outputSize: CGSize
) throws -> CVPixelBuffer {
    let context = CIContext()

    let primaryImage = CIImage(cvPixelBuffer: primary)
    let miniImage = CIImage(cvPixelBuffer: mini)

    // Scale mini to 1/4 size
    let scale: CGFloat = 0.25
    let scaledMini = miniImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    // Position based on corner
    let offset = calculateOffset(for: position, outputSize: outputSize, miniSize: scaledMini.extent.size)
    let positionedMini = scaledMini.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))

    // Composite
    let composited = positionedMini.composited(over: primaryImage)

    // Render to pixel buffer
    var outputBuffer: CVPixelBuffer?
    let attributes = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ] as CFDictionary

    CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(outputSize.width),
        Int(outputSize.height),
        kCVPixelFormatType_32BGRA,
        attributes,
        &outputBuffer
    )

    guard let buffer = outputBuffer else { throw DualCameraError.captureFailure(.memoryAllocationFailed) }

    context.render(composited, to: buffer)
    return buffer
}
```

**Option B: Metal** (Faster, more control)
```swift
// Use existing Metal infrastructure
// Write custom shader to composite frames
```

#### 1.4 Update DualCameraController
**File**: `Sources/DualCameraKit/DualCameraController.swift`

```swift
public final class DualCameraController {
    // NEW: Add stream-based capturer
    private let streamPhotoCapturer = DualCameraStreamPhotoCapturer()

    // Keep old screenshot capturer for backward compatibility
    private let legacyPhotoCapturer = DualCameraPhotoCapturer()

    // Add flag to choose which capturer to use
    private let useStreamCapture: Bool

    public init(useStreamCapture: Bool = true) { // Default to new approach
        self.useStreamCapture = useStreamCapture
    }

    public func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage {
        if useStreamCapture {
            // Use new stream-based capture
            let frontRenderer = getRenderer(for: .front)
            let backRenderer = getRenderer(for: .back)

            // Determine output size from mode
            let outputSize = calculateOutputSize(for: mode)

            return try await streamPhotoCapturer.captureComposedPhoto(
                frontRenderer: frontRenderer,
                backRenderer: backRenderer,
                layout: cameraLayout, // Need to pass this in or access from ViewModel
                outputSize: outputSize
            )
        } else {
            // Fallback to legacy screenshot capture
            return try await legacyPhotoCapturer.captureCurrentScreen(mode: mode)
        }
    }
}
```

---

## Phase 2: Video from Streams

### Implementation Tasks

#### 2.1 Create Stream-based Video Recorder
**New File**: `Sources/DualCameraKit/DualCameraStreamVideoRecorder.swift`

```swift
/// Records video by composing camera streams in real-time
public actor DualCameraStreamVideoRecorder: DualCameraVideoRecording {

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let frontRenderer: CameraRenderer
    private let backRenderer: CameraRenderer
    private let layout: DualCameraLayout
    private let compositor: DualCameraStreamCompositor // Reuse from photo

    func startVideoRecording() async throws {
        // 1. Setup AVAssetWriter for high resolution
        // 2. Start consuming frames from both streams
        // 3. Compose each frame pair in real-time
        // 4. Write composed frames to video
    }

    private func processFrames() async {
        // Consume from both streams simultaneously
        // Compose and write at 30/60 fps
    }
}
```

---

## Migration Strategy

### ✅ **Backward Compatible Approach**
1. Implement new stream-based capture alongside existing screenshot capture
2. Add `useStreamCapture` flag (default: `false` initially)
3. Test thoroughly with flag enabled
4. Once stable, flip default to `true`
5. Eventually deprecate screenshot approach in v2.0

### API Impact
```swift
// Existing (still works)
DualCameraViewModel()

// New (opt-in to stream capture)
DualCameraViewModel(useStreamCapture: true)
```

---

## Testing Plan
1. Unit tests for composition engine
2. Compare output quality: screenshot vs stream
3. Performance benchmarks
4. Test all layouts (PiP, split, etc.)

---

## Timeline Estimate
- **Phase 1 (Photos)**: 3-5 days
  - Day 1: Add buffer capture to renderers
  - Day 2-3: Implement composition engine
  - Day 4: Integration & testing
  - Day 5: Polish & edge cases

- **Phase 2 (Video)**: 5-7 days
  - Day 1-2: Adapt compositor for real-time
  - Day 3-4: Implement video recorder
  - Day 5-6: Testing & optimization
  - Day 7: Documentation

**Total**: ~2 weeks for production-ready implementation
