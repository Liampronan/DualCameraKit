@_spi(Testing) import DualCameraKit
import Foundation
import XCTest

final class DualCameraContentGeometryTests: XCTestCase {
    func test_previewScaleMatchesComposedCaptureContentRect() {
        let sourceSizes = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 100, height: 100)
        ]
        let targetRects = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 20, y: 10, width: 160, height: 90),
            CGRect(x: 0, y: 40, width: 90, height: 160)
        ]
        let contentModes: [DualCameraContentMode] = [.aspectFill, .aspectFit]

        for sourceSize in sourceSizes {
            for targetRect in targetRects {
                for contentMode in contentModes {
                    let captureRect = DualCameraContentGeometry.contentRect(
                        for: sourceSize,
                        in: targetRect,
                        contentMode: contentMode
                    )
                    let previewScale = DualCameraContentGeometry.rendererScale(
                        for: sourceSize,
                        in: targetRect.size,
                        contentMode: contentMode
                    )

                    XCTAssertEqual(
                        CGFloat(previewScale.x),
                        captureRect.width / targetRect.width,
                        accuracy: 0.0001
                    )
                    XCTAssertEqual(
                        CGFloat(previewScale.y),
                        captureRect.height / targetRect.height,
                        accuracy: 0.0001
                    )
                    XCTAssertEqual(captureRect.midX, targetRect.midX, accuracy: 0.0001)
                    XCTAssertEqual(captureRect.midY, targetRect.midY, accuracy: 0.0001)
                }
            }
        }
    }

    func test_previewAndComposedCaptureGeometrySnapshot() {
        let resolver = DualCameraLayoutResolver()
        let sourceSizes: [DualCameraSource: CGSize] = [
            .front: CGSize(width: 160, height: 90),
            .back: CGSize(width: 90, height: 160)
        ]
        let layouts: [(name: String, layout: DualCameraLayout)] = [
            ("sideBySide", .sideBySide),
            ("stackedVertical", .stackedVertical)
        ]
        let contentModes: [(name: String, mode: DualCameraContentMode)] = [
            ("aspectFill", .aspectFill),
            ("aspectFit", .aspectFit)
        ]

        let actual = layouts.flatMap { layoutCase in
            let resolvedLayout = resolver.resolve(layout: layoutCase.layout, in: CGSize(width: 320, height: 240))

            return contentModes.flatMap { contentMode in
                resolvedLayout.regionsInDrawingOrder.map { region in
                    let sourceSize = sourceSizes[region.source] ?? .zero
                    let captureRect = DualCameraContentGeometry.contentRect(
                        for: sourceSize,
                        in: region.frame,
                        contentMode: contentMode.mode
                    )
                    let previewScale = DualCameraContentGeometry.rendererScale(
                        for: sourceSize,
                        in: region.frame.size,
                        contentMode: contentMode.mode
                    )

                    return [
                        layoutCase.name,
                        contentMode.name,
                        String(describing: region.source),
                        "frame=\(format(region.frame))",
                        "capture=\(format(captureRect))",
                        "previewScale=\(format(previewScale))"
                    ].joined(separator: " ")
                }
            }
        }
        .joined(separator: "\n")

        XCTAssertEqual(
            actual,
            """
            sideBySide aspectFill back frame=(0.000,0.000,160.000,240.000) capture=(0.000,-22.222,160.000,284.444) previewScale=(1.000,1.185)
            sideBySide aspectFill front frame=(160.000,0.000,160.000,240.000) capture=(26.667,0.000,426.667,240.000) previewScale=(2.667,1.000)
            sideBySide aspectFit back frame=(0.000,0.000,160.000,240.000) capture=(12.500,0.000,135.000,240.000) previewScale=(0.844,1.000)
            sideBySide aspectFit front frame=(160.000,0.000,160.000,240.000) capture=(160.000,75.000,160.000,90.000) previewScale=(1.000,0.375)
            stackedVertical aspectFill back frame=(0.000,0.000,320.000,120.000) capture=(0.000,-224.444,320.000,568.889) previewScale=(1.000,4.741)
            stackedVertical aspectFill front frame=(0.000,120.000,320.000,120.000) capture=(0.000,90.000,320.000,180.000) previewScale=(1.000,1.500)
            stackedVertical aspectFit back frame=(0.000,0.000,320.000,120.000) capture=(126.250,0.000,67.500,120.000) previewScale=(0.211,1.000)
            stackedVertical aspectFit front frame=(0.000,120.000,320.000,120.000) capture=(53.333,120.000,213.333,120.000) previewScale=(0.667,1.000)
            """
        )
    }

    private func format(_ rect: CGRect) -> String {
        "(\(format(rect.origin.x)),\(format(rect.origin.y)),\(format(rect.size.width)),\(format(rect.size.height)))"
    }

    private func format(_ scale: SIMD2<Float>) -> String {
        "(\(format(CGFloat(scale.x))),\(format(CGFloat(scale.y))))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }
}
