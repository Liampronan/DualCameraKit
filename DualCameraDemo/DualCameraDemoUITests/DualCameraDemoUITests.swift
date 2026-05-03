//
//  DualCameraDemoUITests.swift
//  DualCameraDemoUITests
//
//  Created by Liam Ronan on 2/19/25.
//

import XCTest
import UIKit

final class DualCameraDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testCameraPreviewKeepsAnimatingAcrossDemoModeSwitches() throws {
        let app = XCUIApplication()
        app.launch()

        try assertPreviewAdvances()
        tapDemoMode("Drop-in", in: app)
        try assertPreviewAdvances()
        tapDemoMode("Container", in: app)
        try assertPreviewAdvances()

        tapDemoMode("Compositional", in: app)
        XCTAssertTrue(app.buttons["Top Left"].waitForExistence(timeout: 2))
        app.buttons["Top Left"].tap()
        try assertPreviewAdvances()
    }

    @MainActor
    private func tapDemoMode(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Missing demo mode: \(title)")
        button.tap()
    }

    private func assertPreviewAdvances(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let first = try samplePreviewPixel()
        Thread.sleep(forTimeInterval: 0.75)
        let second = try samplePreviewPixel()

        XCTAssertGreaterThan(
            colorDistance(first, second),
            20,
            "Expected the simulator mock camera stream to keep animating.",
            file: file,
            line: line
        )
    }

    private func samplePreviewPixel() throws -> RGB {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            throw XCTSkip("Could not read app screenshot")
        }

        let width = cgImage.width
        let height = cgImage.height
        let x = Int(CGFloat(width) * 0.5)
        let y = Int(CGFloat(height) * 0.45)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Could not create screenshot sampling context")
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let offset = (y * bytesPerRow) + (x * bytesPerPixel)
        return RGB(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }

    private func colorDistance(_ lhs: RGB, _ rhs: RGB) -> Int {
        abs(Int(lhs.red) - Int(rhs.red)) +
            abs(Int(lhs.green) - Int(rhs.green)) +
            abs(Int(lhs.blue) - Int(rhs.blue))
    }
}

private struct RGB {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}
