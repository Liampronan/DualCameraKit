/// Explicit dependencies used by UI conveniences and app-level composition.
@MainActor
public struct DualCameraDependencies {
    public var mediaLibraryService: MediaLibraryService
    public var makeDualCameraController: @MainActor () -> DualCameraControlling

    public init(
        mediaLibraryService: MediaLibraryService = .live(),
        makeDualCameraController: @escaping @MainActor () -> DualCameraControlling = Self.makeDefaultCameraController
    ) {
        self.mediaLibraryService = mediaLibraryService
        self.makeDualCameraController = makeDualCameraController
    }

    public init(
        mediaLibraryService: MediaLibraryService = .live(),
        dualCameraController: DualCameraControlling
    ) {
        self.init(
            mediaLibraryService: mediaLibraryService,
            makeDualCameraController: { dualCameraController }
        )
    }

    public var dualCameraController: DualCameraControlling {
        makeDualCameraController()
    }

    public static func live(
        mediaLibraryService: MediaLibraryService = .live(),
        makeDualCameraController: @escaping @MainActor () -> DualCameraControlling = Self.makeDefaultCameraController
    ) -> Self {
        Self(
            mediaLibraryService: mediaLibraryService,
            makeDualCameraController: makeDualCameraController
        )
    }

    public static func preview(
        mediaLibraryService: MediaLibraryService = .noop,
        animated: Bool = true
    ) -> Self {
        Self(
            mediaLibraryService: mediaLibraryService,
            makeDualCameraController: {
                DualCameraController(streamSource: DualCameraMockCameraStreamSource(animated: animated))
            }
        )
    }

    public static func makeDefaultCameraController() -> DualCameraControlling {
#if targetEnvironment(simulator)
        return DualCameraController(streamSource: DualCameraMockCameraStreamSource(animated: true))
#else
        return DualCameraController()
#endif
    }
}
