import CoreGraphics
import DualCameraKit
import SwiftUI
import XCTest

final class DualCameraLayoutResolverTests: XCTestCase {
    func test_sideBySideSplitsWidth() {
        let layout = DualCameraLayoutResolver().resolve(layout: .sideBySide, in: CGSize(width: 400, height: 800))

        XCTAssertEqual(layout.background.source, .back)
        XCTAssertEqual(layout.background.frame, CGRect(x: 0, y: 0, width: 200, height: 800))
        XCTAssertEqual(layout.overlay?.source, .front)
        XCTAssertEqual(layout.overlay?.frame, CGRect(x: 200, y: 0, width: 200, height: 800))
    }

    func test_stackedVerticalSplitsHeight() {
        let layout = DualCameraLayoutResolver().resolve(layout: .stackedVertical, in: CGSize(width: 400, height: 800))

        XCTAssertEqual(layout.background.source, .back)
        XCTAssertEqual(layout.background.frame, CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertEqual(layout.overlay?.source, .front)
        XCTAssertEqual(layout.overlay?.frame, CGRect(x: 0, y: 400, width: 400, height: 400))
    }

    func test_pipResolvesMiniCameraPosition() {
        let layout = DualCameraLayoutResolver().resolve(
            layout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
            in: CGSize(width: 400, height: 800)
        )

        XCTAssertEqual(layout.background.source, .back)
        XCTAssertEqual(layout.background.frame, CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(layout.overlay?.source, .front)
        assertEqual(layout.overlay?.frame, CGRect(x: 232, y: 513.7777777777778, width: 152, height: 270.22222222222223))
    }

    func test_pipRespectsOverlayInsets() {
        let layout = DualCameraLayoutResolver().resolve(
            layout: .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing),
            in: CGSize(width: 400, height: 800),
            overlayInsets: EdgeInsets(top: 120, leading: 8, bottom: 120, trailing: 8)
        )

        XCTAssertEqual(layout.background.source, .back)
        XCTAssertEqual(layout.background.frame, CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(layout.overlay?.source, .front)
        assertEqual(
            layout.overlay?.frame,
            CGRect(x: 224, y: 393.77777777777777, width: 152, height: 270.22222222222223)
        )
    }

    private func assertEqual(_ lhs: CGRect?, _ rhs: CGRect, accuracy: CGFloat = 0.001) {
        guard let lhs else {
            XCTFail("Expected a rect")
            return
        }

        XCTAssertEqual(lhs.origin.x, rhs.origin.x, accuracy: accuracy)
        XCTAssertEqual(lhs.origin.y, rhs.origin.y, accuracy: accuracy)
        XCTAssertEqual(lhs.size.width, rhs.size.width, accuracy: accuracy)
        XCTAssertEqual(lhs.size.height, rhs.size.height, accuracy: accuracy)
    }
}
