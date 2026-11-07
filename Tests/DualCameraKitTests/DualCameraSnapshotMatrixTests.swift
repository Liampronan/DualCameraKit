@_spi(Testing) @testable import DualCameraKit
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DualCameraSnapshotMatrixTests: XCTestCase {
    private struct RegionSampleCheck {
        let region: DualCameraResolvedLayout.CameraRegion
        let sourceSize: CGSize
        let contentMode: DualCameraContentMode
        let mirrored: Bool
        let context: String
    }

    private let portrait3x4Size = CGSize(width: 240, height: 320)
    private let portrait9x16Size = CGSize(width: 180, height: 320)
    private let outputSize = CGSize(width: 360, height: 640)
    private let resolver = DualCameraLayoutResolver()

    func test_pipAllCornersMatrixAcrossAspectRatiosAndContentModes() async throws {
        let positions: [DualCameraLayout.MiniCameraPosition] = [
            .topLeading,
            .topTrailing,
            .bottomLeading,
            .bottomTrailing
        ]
        let frameSizes = [portrait3x4Size, portrait9x16Size]
        let contentModes: [DualCameraContentMode] = [.aspectFill, .aspectFit]

        for frameSize in frameSizes {
            let source = DualCameraMockCameraStreamSource.testPattern(
                frontFrameSize: frameSize,
                backFrameSize: frameSize
            )
            let controller = DualCameraController(streamSource: source)
            try await controller.startSession()

            for position in positions {
                for contentMode in contentModes {
                    let layout = DualCameraLayout.piP(miniCamera: .front, miniCameraPosition: position)
                    let resolved = resolver.resolve(layout: layout, in: outputSize)
                    let overlayRegion = try XCTUnwrap(resolved.overlay)

                    let image = try await controller.capturePhoto(
                        layout: layout,
                        outputSize: outputSize,
                        displayScale: 1,
                        contentMode: contentMode
                    )

                    try assertRegionSample(
                        in: image,
                        check: RegionSampleCheck(
                            region: overlayRegion,
                            sourceSize: frameSize,
                            contentMode: contentMode,
                            mirrored: false,
                            context: "PiP \(position) \(contentMode) \(frameSize)"
                        )
                    )
                }
            }
        }
    }

    func test_sideBySideAndStackedVerticalMatrixAcrossAspectRatiosAndContentModes() async throws {
        let layouts: [DualCameraLayout] = [.sideBySide, .stackedVertical]
        let frameSizes = [portrait3x4Size, portrait9x16Size]
        let contentModes: [DualCameraContentMode] = [.aspectFill, .aspectFit]

        for frameSize in frameSizes {
            let source = DualCameraMockCameraStreamSource.testPattern(
                frontFrameSize: frameSize,
                backFrameSize: frameSize
            )
            let controller = DualCameraController(streamSource: source)
            try await controller.startSession()

            for layout in layouts {
                let resolved = resolver.resolve(layout: layout, in: outputSize)
                for contentMode in contentModes {
                    let image = try await controller.capturePhoto(
                        layout: layout,
                        outputSize: outputSize,
                        displayScale: 1,
                        contentMode: contentMode
                    )

                    for region in resolved.regionsInDrawingOrder {
                        try assertRegionSample(
                            in: image,
                            check: RegionSampleCheck(
                                region: region,
                                sourceSize: frameSize,
                                contentMode: contentMode,
                                mirrored: false,
                                context: "\(layout) \(region.source) \(contentMode) \(frameSize)"
                            )
                        )
                    }
                }
            }
        }
    }

    func test_frontCameraMirroringFlipsCornerMarkersHorizontallyInMatrix() async throws {
        let source = DualCameraMockCameraStreamSource.testPattern(
            frontFrameSize: portrait3x4Size,
            backFrameSize: portrait3x4Size,
            mirrorsFrontCamera: true
        )
        let controller = DualCameraController(streamSource: source)
        try await controller.startSession()

        // Use exact matching aspect ratio (240x320 per side in 480x320 sideBySide)
        // so all 4 corner markers are uncropped.
        let exactSideBySideSize = CGSize(width: 480, height: 320)
        let mirroredImage = try await controller.capturePhoto(
            layout: .sideBySide,
            outputSize: exactSideBySideSize,
            displayScale: 1,
            contentMode: .aspectFit
        )

        // Back camera (left half, x: 0..<240) is unmirrored: TL is red, TR is green.
        let backTL = try mirroredImage.rgbPixel(pixelX: 12, pixelY: 12)
        let backTR = try mirroredImage.rgbPixel(pixelX: 240 - 12, pixelY: 12)
        XCTAssertTrue(backTL.isNear(DualCameraTestPattern.Corner.topLeft.color), "Back TL was \(backTL)")
        XCTAssertTrue(backTR.isNear(DualCameraTestPattern.Corner.topRight.color), "Back TR was \(backTR)")

        // Front camera (right half, x: 240..<480) is horizontally mirrored:
        // Left side of front region shows TR marker (green), right side shows TL marker (red).
        let frontLeftTop = try mirroredImage.rgbPixel(pixelX: 240 + 12, pixelY: 12)
        let frontRightTop = try mirroredImage.rgbPixel(pixelX: 480 - 12, pixelY: 12)
        XCTAssertTrue(
            frontLeftTop.isNear(DualCameraTestPattern.Corner.topRight.color),
            "Mirrored front top-left pixel should be TR colour (green), got \(frontLeftTop)"
        )
        XCTAssertTrue(
            frontRightTop.isNear(DualCameraTestPattern.Corner.topLeft.color),
            "Mirrored front top-right pixel should be TL colour (red), got \(frontRightTop)"
        )
    }

    // MARK: - Helpers

    private func assertRegionSample(
        in image: UIImage,
        check: RegionSampleCheck
    ) throws {
        let regionRect = check.region.frame
        let cameraSource = check.region.source
        let fittedRect = DualCameraContentGeometry.contentRect(
            for: check.sourceSize,
            in: regionRect,
            contentMode: check.contentMode
        )
        let visibleContentRect = fittedRect.intersection(regionRect)
        XCTAssertFalse(visibleContentRect.isEmpty, "Empty visible content rect for \(check.context)")

        // Sample background area inside the fitted content rect (clear of grid/text/markers).
        let sampleX = Int((fittedRect.minX + fittedRect.width * 0.22).rounded())
        let sampleY = Int((fittedRect.minY + fittedRect.height * 0.82).rounded())
        if regionRect.contains(CGPoint(x: sampleX, y: sampleY)) {
            let bgPixel = try image.rgbPixel(pixelX: sampleX, pixelY: sampleY)
            XCTAssertTrue(
                bgPixel.isNear(DualCameraTestPattern.backgroundColor(for: cameraSource), tolerance: 18),
                "\(check.context): expected \(cameraSource) background at (\(sampleX), \(sampleY)), got \(bgPixel)"
            )
        }

        if check.contentMode == .aspectFit {
            let markerDimension = min(fittedRect.width, fittedRect.height)
            let topLeftX = Int((fittedRect.minX + markerDimension * 0.09).rounded())
            let topLeftY = Int((fittedRect.minY + markerDimension * 0.025).rounded())
            let expectedCorner: DualCameraTestPattern.Corner = check.mirrored ? .topRight : .topLeft
            let cornerPixel = try image.rgbPixel(pixelX: topLeftX, pixelY: topLeftY)
            XCTAssertTrue(
                cornerPixel.isNear(expectedCorner.color, tolerance: 24),
                "\(check.context): expected \(expectedCorner) marker at (\(topLeftX), \(topLeftY)), got \(cornerPixel)"
            )

            if fittedRect.minY - regionRect.minY >= 6 {
                let letterboxX = Int(regionRect.midX.rounded())
                let letterboxY = Int((regionRect.minY + 2).rounded())
                let barPixel = try image.rgbPixel(pixelX: letterboxX, pixelY: letterboxY)
                XCTAssertTrue(
                    barPixel.isNear(.black, tolerance: 8),
                    "\(check.context): expected black letterbox, got \(barPixel)"
                )
            } else if fittedRect.minX - regionRect.minX >= 6 {
                let pillarboxX = Int((regionRect.minX + 2).rounded())
                let pillarboxY = Int(regionRect.midY.rounded())
                let barPixel = try image.rgbPixel(pixelX: pillarboxX, pixelY: pillarboxY)
                XCTAssertTrue(
                    barPixel.isNear(.black, tolerance: 8),
                    "\(check.context): expected black pillarbox, got \(barPixel)"
                )
            }
        }
    }
}
