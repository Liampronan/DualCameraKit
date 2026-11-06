import AVFoundation
@testable import DualCameraKit
import UIKit
import XCTest

@MainActor
final class DualCameraMockFixtureTests: XCTestCase {
    private let frontSize = CGSize(width: 300, height: 400)
    private let backSize = CGSize(width: 300, height: 400)

    // MARK: - Test pattern

    func test_testPatternImageHasRequestedPixelSize() throws {
        let image = DualCameraTestPattern.image(for: .front, size: CGSize(width: 300, height: 400))

        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(image.cgImage?.width, 300)
        XCTAssertEqual(image.cgImage?.height, 400)
    }

    func test_testPatternDrawsColouredMarkerInEveryCorner() throws {
        let size = CGSize(width: 300, height: 400)
        let image = DualCameraTestPattern.image(for: .back, size: size)

        for corner in DualCameraTestPattern.Corner.allCases {
            let point = Self.outerSamplePoint(for: corner, in: size)
            let pixel = try image.rgbPixel(pixelX: point.x, pixelY: point.y)
            XCTAssertTrue(pixel.isNear(corner.color), "\(corner) marker was \(pixel)")
        }
        let background = try image.rgbPixel(pixelX: 60, pixelY: 330)
        XCTAssertTrue(background.isNear(DualCameraTestPattern.backgroundColor(for: .back)), "\(background)")
    }

    func test_testPatternDefaultsToPortrait3x4() {
        XCTAssertEqual(DualCameraTestPattern.defaultFrameSize, CGSize(width: 1080, height: 1440))
    }

    // MARK: - Mock stream source inits

    func test_testPatternSourcePublishesFramesAtConfiguredSizes() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern(
            frontFrameSize: CGSize(width: 240, height: 320),
            backFrameSize: CGSize(width: 180, height: 320)
        )

        try await source.startSession()

        XCTAssertEqual(source.latestFrame(for: .front)?.buffer.pixelSize, CGSize(width: 240, height: 320))
        XCTAssertEqual(source.latestFrame(for: .back)?.buffer.pixelSize, CGSize(width: 180, height: 320))
        XCTAssertNotNil(source.latestFramePair())
    }

    func test_testPatternSourceUsesDefaultFrameSize() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern()

        try await source.startSession()

        XCTAssertEqual(source.latestFrame(for: .front)?.buffer.pixelSize, DualCameraTestPattern.defaultFrameSize)
        XCTAssertEqual(source.latestFrame(for: .back)?.buffer.pixelSize, DualCameraTestPattern.defaultFrameSize)
    }

    func test_imageSourceServesEachCameraItsOwnImage() async throws {
        let source = DualCameraMockCameraStreamSource(
            front: Self.solidImage(.red, size: CGSize(width: 40, height: 30)),
            back: Self.solidImage(.blue, size: CGSize(width: 30, height: 40))
        )

        try await source.startSession()

        let front = try XCTUnwrap(source.latestFrame(for: .front)?.buffer)
        let back = try XCTUnwrap(source.latestFrame(for: .back)?.buffer)
        XCTAssertEqual(front.pixelSize, CGSize(width: 40, height: 30))
        XCTAssertEqual(back.pixelSize, CGSize(width: 30, height: 40))
        XCTAssertTrue(try front.rgbPixel(pixelX: 5, pixelY: 5).isNear(.red))
        XCTAssertTrue(try back.rgbPixel(pixelX: 5, pixelY: 5).isNear(.blue))
    }

    func test_imageSourceAppliesImageOrientation() async throws {
        // A 40x20 image, red on the left half, rotated a quarter turn clockwise for display (.right):
        // the displayed image is 20x40 with red on the top half.
        let landscape = Self.splitImage(left: .red, right: .blue, size: CGSize(width: 40, height: 20))
        let rotated = UIImage(cgImage: try XCTUnwrap(landscape.cgImage), scale: 1, orientation: .right)
        let source = DualCameraMockCameraStreamSource(front: rotated, back: rotated)

        try await source.startSession()

        let front = try XCTUnwrap(source.latestFrame(for: .front)?.buffer)
        XCTAssertEqual(front.pixelSize, CGSize(width: 20, height: 40))
        XCTAssertTrue(try front.rgbPixel(pixelX: 10, pixelY: 5).isNear(.red))
        XCTAssertTrue(try front.rgbPixel(pixelX: 10, pixelY: 35).isNear(.blue))
    }

    func test_frameProviderSourceReceivesCameraAndFrameIndex() async throws {
        var calls: [String] = []
        let source = DualCameraMockCameraStreamSource { cameraSource, frameIndex in
            calls.append("\(cameraSource)-\(frameIndex)")
            return Self.solidImage(cameraSource == .front ? .red : .blue, size: CGSize(width: 10, height: 10))
        }

        try await source.startSession()

        XCTAssertEqual(calls, ["front-0", "back-0"])
        let back = try XCTUnwrap(source.latestFrame(for: .back)?.buffer)
        XCTAssertTrue(try back.rgbPixel(pixelX: 1, pixelY: 1).isNear(.blue))
    }

    func test_frameProviderReturningNilSkipsThatCamera() async throws {
        let source = DualCameraMockCameraStreamSource { cameraSource, _ in
            cameraSource == .front ? Self.solidImage(.red, size: CGSize(width: 10, height: 10)) : nil
        }

        try await source.startSession()

        XCTAssertNotNil(source.latestFrame(for: .front))
        XCTAssertNil(source.latestFrame(for: .back))
        XCTAssertNil(source.latestFramePair())
    }

    func test_animatedFrameProviderAdvancesFrameIndex() async throws {
        var frontIndexes: [Int] = []
        let source = DualCameraMockCameraStreamSource(animated: true) { cameraSource, frameIndex in
            if cameraSource == .front { frontIndexes.append(frameIndex) }
            return Self.solidImage(.red, size: CGSize(width: 10, height: 10))
        }

        try await source.startSession()
        try await Task.sleep(for: .milliseconds(600))
        source.stopSession()

        XCTAssertEqual(frontIndexes.first, 0)
        XCTAssertGreaterThanOrEqual(frontIndexes.count, 2)
        XCTAssertEqual(frontIndexes, Array(0..<frontIndexes.count))
    }

    // MARK: - Determinism

    func test_staticSourceDoesNotPublishNewFramesOverTime() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern(frontFrameSize: frontSize, backFrameSize: backSize)
        try await source.startSession()
        let first = try XCTUnwrap(source.latestFrame(for: .front))

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(source.latestFrame(for: .front)?.buffer === first.buffer)
    }

    func test_staticSourceServesIdenticalPixelsAcrossRestarts() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern(frontFrameSize: frontSize, backFrameSize: backSize)
        try await source.startSession()
        let firstBytes = try XCTUnwrap(source.latestFrame(for: .back)).buffer.pixelBytes()

        source.stopSession()
        try await source.startSession()
        let secondBytes = try XCTUnwrap(source.latestFrame(for: .back)).buffer.pixelBytes()

        XCTAssertFalse(firstBytes.isEmpty)
        XCTAssertEqual(firstBytes, secondBytes)
    }

    func test_separateTestPatternSourcesServeIdenticalPixels() async throws {
        let first = DualCameraMockCameraStreamSource.testPattern(frontFrameSize: frontSize, backFrameSize: backSize)
        let second = DualCameraMockCameraStreamSource.testPattern(frontFrameSize: frontSize, backFrameSize: backSize)
        try await first.startSession()
        try await second.startSession()

        for cameraSource in [DualCameraSource.front, .back] {
            let firstBytes = try XCTUnwrap(first.latestFrame(for: cameraSource)).buffer.pixelBytes()
            let secondBytes = try XCTUnwrap(second.latestFrame(for: cameraSource)).buffer.pixelBytes()
            XCTAssertEqual(firstBytes, secondBytes, "\(cameraSource) frames differ")
        }
    }

    // MARK: - Capture through DualCameraController

    func test_sideBySideCaptureShowsEveryMarkerOfBothCameras() async throws {
        let controller = try await makeStartedController()
        // Each half is 300x400, the same aspect as the frames, so nothing is cropped or letterboxed.
        let outputSize = CGSize(width: 600, height: 400)

        let image = try await controller.capturePhoto(layout: .sideBySide, outputSize: outputSize, displayScale: 1)

        XCTAssertEqual(image.size, outputSize)
        // sideBySide puts the back camera on the left and the front camera on the right.
        for (cameraSource, originX) in [(DualCameraSource.back, 0), (.front, 300)] {
            for corner in DualCameraTestPattern.Corner.allCases {
                let point = Self.outerSamplePoint(for: corner, in: frontSize)
                let pixel = try image.rgbPixel(pixelX: originX + point.x, pixelY: point.y)
                XCTAssertTrue(pixel.isNear(corner.color), "\(cameraSource) \(corner) marker was \(pixel)")
            }
            let background = try image.rgbPixel(pixelX: originX + 60, pixelY: 330)
            XCTAssertTrue(
                background.isNear(DualCameraTestPattern.backgroundColor(for: cameraSource)),
                "\(cameraSource) background was \(background)"
            )
        }
    }

    func test_aspectFillIntoNarrowerRegionCropsSideMarkers() async throws {
        let controller = try await makeStartedController()
        // Each half is 150x400 (narrower than the 3:4 frames), so aspect fill crops 75 px from each side
        // of each frame and the corner markers (54 px wide) are cut off entirely.
        let image = try await controller.capturePhoto(
            layout: .sideBySide,
            outputSize: CGSize(width: 300, height: 400),
            displayScale: 1
        )

        let topLeftOfBackHalf = try image.rgbPixel(pixelX: 5, pixelY: 5)
        XCTAssertFalse(topLeftOfBackHalf.isNear(DualCameraTestPattern.Corner.topLeft.color), "\(topLeftOfBackHalf)")
        let leftEdgeOfBackHalf = try image.rgbPixel(pixelX: 5, pixelY: 330)
        XCTAssertTrue(
            leftEdgeOfBackHalf.isNear(DualCameraTestPattern.backgroundColor(for: .back)),
            "\(leftEdgeOfBackHalf)"
        )
    }

    func test_capturedImagePixelSizeIsOutputSizeTimesDisplayScale() async throws {
        let controller = try await makeStartedController()
        let outputSize = CGSize(width: 390, height: 844)

        let image = try await controller.capturePhoto(layout: .stackedVertical, outputSize: outputSize, displayScale: 3)

        XCTAssertEqual(image.size, outputSize)
        XCTAssertEqual(image.scale, 3)
        XCTAssertEqual(image.cgImage?.width, 1170)
        XCTAssertEqual(image.cgImage?.height, 2532)
    }

    func test_rawCaptureReturnsTestPatternFramesAtFrameSize() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern(
            frontFrameSize: CGSize(width: 300, height: 400),
            backFrameSize: CGSize(width: 225, height: 400)
        )
        let controller = DualCameraController(streamSource: source)
        try await controller.startSession()

        let photos = try await controller.captureRawPhotos()

        XCTAssertEqual(photos.front.cgImage?.width, 300)
        XCTAssertEqual(photos.front.cgImage?.height, 400)
        XCTAssertEqual(photos.back.cgImage?.width, 225)
        XCTAssertEqual(photos.back.cgImage?.height, 400)
        XCTAssertTrue(try photos.back.rgbPixel(pixelX: 5, pixelY: 5).isNear(DualCameraTestPattern.Corner.topLeft.color))
    }

    // MARK: - Helpers

    private func makeStartedController() async throws -> DualCameraController {
        let source = DualCameraMockCameraStreamSource.testPattern(frontFrameSize: frontSize, backFrameSize: backSize)
        let controller = DualCameraController(streamSource: source)
        try await controller.startSession()
        return controller
    }

    /// A point inside `corner`'s marker, near the frame corner and clear of the marker's label.
    private static func outerSamplePoint(
        for corner: DualCameraTestPattern.Corner,
        in size: CGSize
    ) -> (x: Int, y: Int) {
        let rect = DualCameraTestPattern.markerRect(for: corner, in: size)
        let inset: CGFloat = 8
        let sampleX = corner == .topLeft || corner == .bottomLeft ? rect.minX + inset : rect.maxX - inset
        let sampleY = corner == .topLeft || corner == .topRight ? rect.minY + inset : rect.maxY - inset
        return (Int(sampleX), Int(sampleY))
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

    private static func splitImage(left: UIColor, right: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            left.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            right.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
    }
}
