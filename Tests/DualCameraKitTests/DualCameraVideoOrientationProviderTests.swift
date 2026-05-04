import Testing
import UIKit
@testable import DualCameraKit

@MainActor
struct DualCameraVideoOrientationProviderTests {
    @Test
    func flatAndUnknownOrientationsPreserveLastValidRotationAngle() {
        let provider = DeviceVideoOrientationProvider()

        #expect(provider.videoRotationAngle(for: .landscapeRight) == 180)
        #expect(provider.videoRotationAngle(for: .faceUp) == 180)
        #expect(provider.videoRotationAngle(for: .faceDown) == 180)
        #expect(provider.videoRotationAngle(for: .unknown) == 180)

        #expect(provider.videoRotationAngle(for: .portraitUpsideDown) == 270)
        #expect(provider.videoRotationAngle(for: .faceUp) == 270)
    }
}
