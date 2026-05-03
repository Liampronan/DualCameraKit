// Public default environment for DualCameraKit.
/// A value-type container for default services,
/// allowing dependency injection with safe, testable defaults.
/// Inspired by https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
///  Trying this out for now. It still feels kinda weird and so
///  at some point it might  be worth  moving it to a more formal DI.
@MainActor
public struct DualCameraEnvironment {
    public var mediaLibraryService: MediaLibraryService
    public var dualCameraController: DualCameraControlling

    public init(
        mediaLibraryService: MediaLibraryService = .live(),
        dualCameraController: DualCameraControlling? = nil
    ) {
        self.mediaLibraryService = mediaLibraryService
        self.dualCameraController = dualCameraController ?? Self.getDefaultCameraController()
    }

    static func getDefaultCameraController() -> DualCameraControlling {
#if targetEnvironment(simulator)
        return DualCameraController(streamSource: DualCameraMockCameraStreamSource())
#else
        return DualCameraController()
#endif
    }
}

// swiftlint:disable:next identifier_name
@MainActor
public var CurrentDualCameraEnvironment = DualCameraEnvironment()
