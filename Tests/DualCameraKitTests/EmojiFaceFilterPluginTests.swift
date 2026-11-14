import AVFoundation
import CoreGraphics
import CoreVideo
@testable import DualCameraEmojiKit
import DualCameraEmojiKitUI
@testable import DualCameraKit
import os
import UIKit
import XCTest

@MainActor
final class EmojiFaceFilterPluginTests: XCTestCase {
    func test_processorRendersOverlayOverDetectedFaceRegion() async throws {
        let baseBuffer = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 120, height: 120))
        let redStickerImage = Self.solidImage(.red, size: CGSize(width: 64, height: 64))
        let redSticker = try XCTUnwrap(EmojiOverlaySticker(id: "red-square", image: redStickerImage))

        let detector = StubFaceDetector(faces: [
            DetectedFace(
                boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30),
                rollAngleRadians: 0
            )
        ])

        let config = EmojiFaceFilterConfiguration(
            targetSources: [.front],
            assignment: .sticker(redSticker),
            scaleMultiplier: 1.0,
            tracksHeadRoll: false
        )
        let processor = EmojiFaceFilterProcessor(
            configuration: config,
            faceDetector: detector,
            clock: { 10.0 }
        )

        let output = await processor.process(
            frame: PixelBufferWrapper(buffer: baseBuffer),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )

        XCTAssertFalse(output.buffer === baseBuffer)
        let centerPixel = try output.buffer.rgbPixel(pixelX: 60, pixelY: 60)
        let cornerPixel = try output.buffer.rgbPixel(pixelX: 5, pixelY: 5)

        XCTAssertTrue(
            centerPixel.isNear(.red, tolerance: 20),
            "Expected center pixel to be red, got \(centerPixel)"
        )
        XCTAssertTrue(
            cornerPixel.isNear(.blue, tolerance: 20),
            "Expected corner pixel to remain blue, got \(cornerPixel)"
        )
    }

    func test_processorPassesThroughUntargetedCameraSource() async throws {
        let baseBuffer = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 64, height: 64))
        let detector = StubFaceDetector(faces: [
            DetectedFace(boundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        ])
        let processor = EmojiFaceFilterProcessor(
            configuration: EmojiFaceFilterConfiguration(targetSources: [.front]),
            faceDetector: detector
        )

        let output = await processor.process(
            frame: PixelBufferWrapper(buffer: baseBuffer),
            context: DualCameraFrameContext(source: .back, isMirrored: false, purpose: .livePreview)
        )

        XCTAssertTrue(output.buffer === baseBuffer)
        XCTAssertEqual(detector.callCount, 0)
    }

    func test_trackerRetainsFaceDuringDropoutGraceWindowAndExpiresAfterward() async throws {
        let redSticker = try XCTUnwrap(
            EmojiOverlaySticker(id: "red", image: Self.solidImage(.red, size: CGSize(width: 64, height: 64)))
        )
        let detector = StubFaceDetector(faces: [
            DetectedFace(boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30))
        ])
        let clockBox = OSAllocatedUnfairLock(initialState: TimeInterval(1.0))

        let processor = EmojiFaceFilterProcessor(
            configuration: EmojiFaceFilterConfiguration(
                assignment: .sticker(redSticker),
                scaleMultiplier: 1.0,
                trackGracePeriod: 0.20
            ),
            faceDetector: detector,
            clock: { clockBox.withLock { $0 } }
        )

        // Frame 1 at t = 1.0s: face detected.
        let frame1 = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 100, height: 100))
        let out1 = await processor.process(
            frame: PixelBufferWrapper(buffer: frame1),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )
        XCTAssertTrue(try out1.buffer.rgbPixel(pixelX: 50, pixelY: 50).isNear(.red, tolerance: 20))

        // Frame 2 at t = 1.10s (within 0.20s grace window): Vision misses the face, overlay stays active.
        detector.setFaces([])
        clockBox.withLock { $0 = 1.10 }
        let frame2 = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 100, height: 100))
        let out2 = await processor.process(
            frame: PixelBufferWrapper(buffer: frame2),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )
        XCTAssertTrue(try out2.buffer.rgbPixel(pixelX: 50, pixelY: 50).isNear(.red, tolerance: 20))

        // Frame 3 at t = 1.35s (past 0.20s grace window): track expires, frame passes through unmodified.
        clockBox.withLock { $0 = 1.35 }
        let frame3 = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 100, height: 100))
        let out3 = await processor.process(
            frame: PixelBufferWrapper(buffer: frame3),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )
        XCTAssertTrue(out3.buffer === frame3)
    }

    func test_redactRawCapturesControlsWhetherRawPhotosAreFiltered() async throws {
        let frontImage = Self.solidImage(.blue, size: CGSize(width: 100, height: 100))
        let backImage = Self.solidImage(.green, size: CGSize(width: 100, height: 100))
        let redSticker = try XCTUnwrap(
            EmojiOverlaySticker(id: "red", image: Self.solidImage(.red, size: CGSize(width: 64, height: 64)))
        )
        let detector = StubFaceDetector(faces: [
            DetectedFace(boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40))
        ])

        let plugin = EmojiFaceFilterPlugin(
            configuration: EmojiFaceFilterConfiguration(
                targetSources: [.front],
                assignment: .sticker(redSticker),
                scaleMultiplier: 1.0,
                redactRawCaptures: true
            ),
            faceDetector: detector
        )

        let streamSource = DualCameraMockCameraStreamSource(
            front: frontImage,
            back: backImage
        )
        let controller = DualCameraController(
            streamSource: streamSource,
            frameProcessor: plugin.processor
        )
        try await controller.startSession()
        defer { controller.stopSession() }

        // 1. With redactRawCaptures = true, frontRaw is redacted (red center) and Vision runs only once per buffer.
        let redactedSet = try await controller.capturePhotoSet(
            layout: .sideBySide,
            outputSize: CGSize(width: 200, height: 100)
        )
        let redactedFrontCenter = try redactedSet.frontRaw.rgbPixel(pixelX: 50, pixelY: 50)
        XCTAssertTrue(redactedFrontCenter.isNear(.red, tolerance: 25), "Got \(redactedFrontCenter)")

        // 2. With redactRawCaptures = false, composed still has red overlay while frontRaw stays unredacted blue.
        plugin.configuration.redactRawCaptures = false
        let unredactedRawSet = try await controller.capturePhotoSet(
            layout: .sideBySide,
            outputSize: CGSize(width: 200, height: 100)
        )
        let unredactedFrontCenter = try unredactedRawSet.frontRaw.rgbPixel(pixelX: 50, pixelY: 50)
        let composedFrontCenter = try unredactedRawSet.composed.rgbPixel(pixelX: 150, pixelY: 50)
        XCTAssertTrue(unredactedFrontCenter.isNear(.blue, tolerance: 25), "Got \(unredactedFrontCenter)")
        XCTAssertTrue(composedFrontCenter.isNear(.red, tolerance: 25), "Got \(composedFrontCenter)")
    }

    func test_noFaceFallbackBlurModifiesFrameWhenNoFaceDetected() async throws {
        // Create a high-contrast half-black, half-white image at 1x scale so Gaussian blur blends the boundary.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80), format: format)
        let splitImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
            UIColor.white.setFill()
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 80))
        }
        let inputBuffer = try XCTUnwrap(splitImage.pixelBuffer())
        let detector = StubFaceDetector(faces: [])

        let processor = EmojiFaceFilterProcessor(
            configuration: EmojiFaceFilterConfiguration(
                noFaceFallback: .blurFrame(radius: 16)
            ),
            faceDetector: detector
        )

        let output = await processor.process(
            frame: PixelBufferWrapper(buffer: inputBuffer),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )

        XCTAssertFalse(output.buffer === inputBuffer)
        let boundaryPixel = try output.buffer.rgbPixel(pixelX: 39, pixelY: 40)
        XCTAssertTrue(
            boundaryPixel.red > 40 && boundaryPixel.red < 215,
            "Expected blurred mid-tone pixel near boundary, got \(boundaryPixel)"
        )
    }

    func test_cycleEmojiOnFaceAdvancesAssignedPaletteEmoji() async throws {
        let baseBuffer = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 120, height: 120))
        let detector = StubFaceDetector(faces: [
            DetectedFace(boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40))
        ])

        let plugin = EmojiFaceFilterPlugin(
            configuration: EmojiFaceFilterConfiguration(
                assignment: .single("😎"),
                scaleMultiplier: 1.2
            ),
            faceDetector: detector
        )

        _ = await plugin.processor.process(
            frame: PixelBufferWrapper(buffer: baseBuffer),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )

        let didCycle = await plugin.cycleEmojiOnFace(
            for: .front,
            atNormalizedTopLeftPoint: CGPoint(x: 0.5, y: 0.5),
            palette: ["😎", "🦊"]
        )
        XCTAssertTrue(didCycle)
        XCTAssertEqual(plugin.configuration.assignment, .palette(["😎", "🦊"]))

        let didMiss = await plugin.cycleEmojiOnFace(
            for: .front,
            atNormalizedTopLeftPoint: CGPoint(x: 0.02, y: 0.02),
            palette: ["😎", "🦊"]
        )
        XCTAssertFalse(didMiss)
    }

    func test_stickerReplacementWithSameIDInvalidatesCachedBitmap() async throws {
        let baseBuffer = try makeSolidPixelBuffer(color: .blue, size: CGSize(width: 100, height: 100))
        let redSticker = try XCTUnwrap(
            EmojiOverlaySticker(id: "avatar", image: Self.solidImage(.red, size: CGSize(width: 64, height: 64)))
        )
        let greenSticker = try XCTUnwrap(
            EmojiOverlaySticker(id: "avatar", image: Self.solidImage(.green, size: CGSize(width: 64, height: 64)))
        )
        let detector = StubFaceDetector(faces: [
            DetectedFace(boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40))
        ])

        let processor = EmojiFaceFilterProcessor(
            configuration: EmojiFaceFilterConfiguration(
                assignment: .sticker(redSticker),
                scaleMultiplier: 1.0
            ),
            faceDetector: detector
        )

        let firstOutput = await processor.process(
            frame: PixelBufferWrapper(buffer: baseBuffer),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )
        XCTAssertTrue(try firstOutput.buffer.rgbPixel(pixelX: 50, pixelY: 50).isNear(.red, tolerance: 20))

        processor.updateConfiguration(
            EmojiFaceFilterConfiguration(
                assignment: .sticker(greenSticker),
                scaleMultiplier: 1.0
            )
        )

        let secondOutput = await processor.process(
            frame: PixelBufferWrapper(buffer: baseBuffer),
            context: DualCameraFrameContext(source: .front, isMirrored: true, purpose: .livePreview)
        )
        XCTAssertTrue(try secondOutput.buffer.rgbPixel(pixelX: 50, pixelY: 50).isNear(.green, tolerance: 20))
    }

    func test_trackerPreservesTrackIdentityAndPaletteOffsetWhenOlderFrameProcessedAfterNewerFrame() async {
        let tracker = FaceTrackerActor()
        let config = EmojiFaceFilterConfiguration(
            scaleMultiplier: 1.0,
            trackGracePeriod: 0.15
        )
        let detection = DetectedFace(
            boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40)
        )

        // 1. Process frame A at t = 1.0s and advance its palette offset.
        let overlaysA1 = await tracker.updateTracks(
            for: .front,
            detections: [detection],
            timestamp: 1.00,
            configuration: config
        )
        XCTAssertEqual(overlaysA1.count, 1)
        let initialTrackID = overlaysA1[0].trackID

        let didCycle = await tracker.cycleEmoji(
            for: .front,
            atNormalizedTopLeftPoint: CGPoint(x: 0.5, y: 0.5),
            scaleMultiplier: 1.0
        )
        XCTAssertTrue(didCycle)

        // 2. Process newer frame B at t = 1.05s.
        let overlaysB = await tracker.updateTracks(
            for: .front,
            detections: [detection],
            timestamp: 1.05,
            configuration: config
        )
        XCTAssertEqual(overlaysB.first?.trackID, initialTrackID)
        XCTAssertEqual(overlaysB.first?.paletteOffset, 1)

        // 3. Re-process older frame A at t = 1.0s; track identity and palette offset must stay continuous.
        let overlaysA2 = await tracker.updateTracks(
            for: .front,
            detections: [detection],
            timestamp: 1.00,
            configuration: config
        )
        XCTAssertEqual(overlaysA2.first?.trackID, initialTrackID)
        XCTAssertEqual(overlaysA2.first?.paletteOffset, 1)

        // 4. Subsequent frame C at t = 1.18s (within 0.15s of B at 1.05s, past 1.00s) still matches B's track.
        let overlaysC = await tracker.updateTracks(
            for: .front,
            detections: [detection],
            timestamp: 1.18,
            configuration: config
        )
        XCTAssertEqual(overlaysC.first?.trackID, initialTrackID)
        XCTAssertEqual(overlaysC.first?.paletteOffset, 1)
    }

    func test_trackerDoesNotReturnFutureTrackAsDropoutOverlayForOlderEmptyFrame() async {
        let tracker = FaceTrackerActor()
        let config = EmojiFaceFilterConfiguration(
            scaleMultiplier: 1.0,
            trackGracePeriod: 0.15
        )
        let detection = DetectedFace(
            boundingBox: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40)
        )

        // 1. Frame A at t = 1.00s has no detections.
        let overlaysA1 = await tracker.updateTracks(
            for: .front,
            detections: [],
            timestamp: 1.00,
            configuration: config
        )
        XCTAssertTrue(overlaysA1.isEmpty)

        // 2. Newer frame B at t = 1.30s detects a face.
        let overlaysB = await tracker.updateTracks(
            for: .front,
            detections: [detection],
            timestamp: 1.30,
            configuration: config
        )
        XCTAssertEqual(overlaysB.count, 1)
        let trackIDFromB = overlaysB[0].trackID

        // 3. Replaying frame A at t = 1.00s with no detections must not leak B's future track as an overlay.
        let overlaysA2 = await tracker.updateTracks(
            for: .front,
            detections: [],
            timestamp: 1.00,
            configuration: config
        )
        XCTAssertTrue(overlaysA2.isEmpty)

        // 4. B's track remains preserved in stored live state for subsequent frame C at t = 1.40s.
        let overlaysC = await tracker.updateTracks(
            for: .front,
            detections: [],
            timestamp: 1.40,
            configuration: config
        )
        XCTAssertEqual(overlaysC.first?.trackID, trackIDFromB)
    }

    private func makeSolidPixelBuffer(color: UIColor, size: CGSize) throws -> CVPixelBuffer {
        guard let buffer = Self.solidImage(color, size: size).pixelBuffer() else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        return buffer
    }

    private static func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class StubFaceDetector: FaceDetectionProviding, Sendable {
    private let state: OSAllocatedUnfairLock<(faces: [DetectedFace], callCount: Int)>

    init(faces: [DetectedFace]) {
        self.state = OSAllocatedUnfairLock(initialState: (faces, 0))
    }

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    func setFaces(_ newFaces: [DetectedFace]) {
        state.withLock { $0.faces = newFaces }
    }

    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [DetectedFace] {
        state.withLock { state in
            state.callCount += 1
            return state.faces
        }
    }
}
