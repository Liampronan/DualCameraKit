# Photo Capture: Two Approaches

## 🎯 Why Two Approaches?

DualCameraKit supports **both** screenshot-based and stream-based photo capture. Each has distinct tradeoffs:

---

## 📸 Approach Comparison

| Feature | Screenshot Capture | Stream Capture |
|---------|-------------------|----------------|
| **Quality** | Screen resolution (~3MP) | Native camera (~12MP) |
| **UI Effects** | ✅ Automatic (SwiftUI) | ⚙️ Configurable (Core Image) |
| **Complexity** | Simple | Moderate |
| **Performance** | CPU-heavy | GPU-accelerated |
| **File Size** | Smaller | Larger |
| **Best For** | Quick integration, UI matters | Production quality |

---

## 🔄 The Fundamental Difference

### Screenshot Capture
```
┌──────────────────────────────────────┐
│ Camera Streams                       │
│   ↓                                  │
│ Metal Renderers (display)            │
│   ↓                                  │
│ SwiftUI View Hierarchy               │
│   • Rounded corners (.cornerRadius)  │
│   • Shadows (.shadow)                │
│   • Borders (.stroke)                │
│   • All SwiftUI modifiers            │
│   ↓                                  │
│ Screenshot API                       │
│   ↓                                  │
│ Final Image (with all UI effects)    │
└──────────────────────────────────────┘
```

**Pros:**
- ✅ Zero configuration - UI effects automatic
- ✅ What You See Is What You Get (WYSIWYG)
- ✅ Easy to integrate

**Cons:**
- ❌ Limited to screen resolution
- ❌ CPU-intensive
- ❌ Captures UI artifacts if any

---

### Stream Capture
```
┌──────────────────────────────────────┐
│ Camera Streams (Native Resolution)   │
│   ↓                                  │
│ Raw Pixel Buffers                    │
│   ↓                                  │
│ Core Image Composition               │
│   • Programmatic layout              │
│   • Configurable effects:            │
│     - Rounded corners (mask)         │
│     - Shadows (CGContext)            │
│     - Borders (stroke)               │
│   ↓                                  │
│ High-Resolution Image                │
└──────────────────────────────────────┘
```

**Pros:**
- ✅ Native camera resolution (12MP+)
- ✅ GPU-accelerated
- ✅ Clean raw output
- ✅ Configurable styling

**Cons:**
- ⚙️ Requires UI recreation
- ⚙️ More complex

---

## 💡 Solution: Configurable Styling

Stream capture now supports **out-of-the-box UI effects** that match `DualCameraScreen`:

### Default Style (Matches SwiftUI)
```swift
let controller = DualCameraController(
    useStreamCapture: true,
    photoStyle: .dualCameraScreen  // ← Rounded corners + shadow + border
)
```

**Result:** High-res photo with same visual appearance as SwiftUI!

### Custom Style
```swift
let customStyle = DualCameraPhotoStyle(
    miniCameraCornerRadius: 20,
    miniCameraShadow: .init(
        color: .black,
        radius: 15,
        opacity: 0.6,
        offset: CGSize(width: 0, height: 8)
    ),
    miniCameraBorder: .init(color: .white, width: 3)
)

let controller = DualCameraController(
    useStreamCapture: true,
    photoStyle: customStyle
)
```

### Minimal Style (No Effects)
```swift
let controller = DualCameraController(
    useStreamCapture: true,
    photoStyle: .minimal  // ← Clean, raw composition
)
```

**Use case:** When you want to apply custom post-processing

---

## 🎨 Style Configuration API

```swift
public struct DualCameraPhotoStyle {
    let miniCameraCornerRadius: CGFloat
    let miniCameraShadow: ShadowStyle?
    let miniCameraBorder: BorderStyle?

    struct ShadowStyle {
        let color: UIColor
        let radius: CGFloat
        let opacity: Float
        let offset: CGSize
    }

    struct BorderStyle {
        let color: UIColor
        let width: CGFloat
    }
}
```

### Presets

| Preset | Description |
|--------|-------------|
| `.dualCameraScreen` | Matches SwiftUI appearance (12pt corners, shadow, border) |
| `.minimal` | No effects - raw composition |
| `.custom` | Build your own |

---

## 🚀 Usage Examples

### Example 1: High Quality with SwiftUI Look
```swift
// Best of both worlds: Native res + familiar UI
let controller = DualCameraController(
    useStreamCapture: true,
    photoStyle: .dualCameraScreen
)
```

### Example 2: Raw for Custom Post-Processing
```swift
// Get clean composition, apply your own effects
let controller = DualCameraController(
    useStreamCapture: true,
    photoStyle: .minimal
)

// Later: Apply filters, adjust, etc.
let rawPhoto = try await controller.captureComposedPhoto(...)
let filtered = applyMyCustomFilters(rawPhoto)
```

### Example 3: Quick Integration (Screenshot)
```swift
// Just want it to work? Use screenshot
let controller = DualCameraController(
    useStreamCapture: false  // Screenshot - includes all SwiftUI
)
```

---

## 📊 Decision Matrix

### Choose **Screenshot Capture** if:
- ✅ Quality is "good enough" at screen res
- ✅ You want instant SwiftUI integration
- ✅ File size matters (smaller images)
- ✅ Prototyping/MVP

### Choose **Stream Capture** if:
- ✅ Need production-quality resolution
- ✅ Want GPU performance
- ✅ Need clean raw output
- ✅ Willing to configure styling

---

## 🔮 Future: Video Recording

Stream capture enables **4K video** using the same composition engine:
```swift
// Phase 2: Coming soon!
let recorder = DualCameraStreamVideoRecorder(
    layout: .piP(...),
    style: .dualCameraScreen,  // Same styling system
    quality: .fourK60fps
)
```

---

## 🎓 Technical Details

### How Styling Works

#### Rounded Corners
```swift
// Uses Core Image blend mask
let maskImage = createRoundedRectMask(radius: 12)
let filter = CIFilter(name: "CIBlendWithMask")
filter.setValue(image, forKey: kCIInputImageKey)
filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
```

#### Shadows
```swift
// Uses CGContext shadow API
cgContext.setShadow(
    offset: CGSize(width: 0, height: 4),
    blur: 10,
    color: UIColor.black.withAlphaComponent(0.3).cgColor
)
cgContext.draw(image, in: rect)
```

#### Borders
```swift
// Draws stroke path over image
let path = UIBezierPath(rect: rect)
path.lineWidth = 2
UIColor.white.setStroke()
path.stroke()
```

---

## 🎯 Recommended Strategy

### For Most Apps
1. Start with **screenshot** for MVP
2. Switch to **stream + .dualCameraScreen style** for production
3. A/B test to measure quality impact

### For High-End Apps
1. Use **stream + .dualCameraScreen** from day 1
2. Offer "HD mode" toggle in settings
3. Let users choose quality vs file size

---

## 📝 Summary

**Keep both approaches:**
- Screenshot = Easy, familiar, "good enough"
- Stream = Production quality, configurable, future-proof

**Default styling solves UI recreation:**
```swift
photoStyle: .dualCameraScreen  // Out-of-the-box SwiftUI look
```

**Result:** Best of both worlds! 🎉
