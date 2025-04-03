import UIKit

// Public default environment for DualCameraScreen.
/// A value-type container for default services,
/// allowing dependency injection with safe, testable defaults.
/// Inspired by https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
///  Trying this out for now. It still feels kinda weird and so
///  at some point it might  be worth  moving it to a more formal DI.
public struct DualCameraEnvironment: Sendable {
    public var mediaLibraryService: MediaLibraryService = .live()
    public var dualCameraController: DualCameraControlling = Self.getDefaultCameraController()
    
    
    @MainActor
    static func getDefaultCameraController() -> DualCameraControlling {
#if targetEnvironment(simulator)
        return DualCameraMockController()
#else
        return DualCameraController()
#endif
    }
}
// swiftlint:disable:next identifier_name
public let CurrentDualCameraEnvironment = DualCameraEnvironment()
