import XCTest
@testable import DualCameraKit

final class MediaLibraryServiceTests: XCTestCase {

    // MARK: - Permission Tests

    func test_saveImage_failsIfPermissionDenied() async {
        let denied: @Sendable () async throws -> Void = {
            throw MediaLibraryError.permissionDenied
        }

        let service = MediaLibraryService.live(
            permissionChecker: denied,
            saveImageHandler: { _ in XCTFail("Should not attempt save") }
        )

        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await service.saveImage(UIImage()))
    }

    // MARK: - Save Handler Invocation Tests

    func test_saveImage_invokesSaveHandlerOnSuccess() async throws {
        let flag = TestBox<Bool>()

        let handler: @Sendable (UIImage) async throws -> Void = { _ in
            await flag.set(true)
        }

        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveImageHandler: handler
        )

        try await service.saveImage(UIImage())
        let res = await flag.get() ?? false
        XCTAssertTrue(res)
    }

    // MARK: - Error Propagation

    func test_saveImage_propagatesErrorsFromSaveHandler() async {
        struct TestError: Error {}

        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveImageHandler: { _ in throw TestError() }
        )

        await XCTAssertThrowsError(ofType: TestError.self, try await service.saveImage(UIImage()))
    }

}
