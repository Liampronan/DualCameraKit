import UIKit

// Public default environment for DualCameraScreen.
/// A value-type container for default services,
/// allowing dependency injection with safe, testable defaults.
/// Inspired by https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
public struct DualCameraEnvironment: Sendable {
    public var mediaLibraryService: MediaLibraryService = .live()
}

public let CurrentDualCameraEnvironment = DualCameraEnvironment()
