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
            saveImageHandler: { _ in XCTFail("Should not attempt save") },
            removeItem: { _ in XCTFail("Should not attempt cleanup") }
        )

        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await service.saveImage(UIImage()))
    }

    func test_saveVideo_failsIfPermissionDenied() async {
        let denied: @Sendable () async throws -> Void = {
            throw MediaLibraryError.permissionDenied
        }

        let service = MediaLibraryService.live(
            permissionChecker: denied,
            saveVideoHandler: { _ in XCTFail("Should not attempt save") },
            removeItem: { _ in XCTFail("Should not attempt cleanup") }
        )

        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await service.saveVideo(.mock()))
    }

    // MARK: - Save Handler Invocation Tests

    func test_saveImage_invokesSaveHandlerOnSuccess() async throws {
        let flag = TestBox<Bool>()

        let handler: @Sendable (UIImage) async throws -> Void = { _ in
            await flag.set(true)
        }

        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveImageHandler: handler,
            removeItem: { _ in }
        )

        try await service.saveImage(UIImage())
        let res = await flag.get() ?? false
        XCTAssertTrue(res)
    }

    func test_saveVideo_invokesSaveHandlerAndRemoveItemOnSuccess() async throws {
        let saveFlag = TestBox<Bool>()
        let removeFlag = TestBox<Bool>()
        let url = URL.mock()

        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveVideoHandler: { input in
                XCTAssertEqual(input, url)
                await saveFlag.set(true)
            },
            removeItem: { input in
                XCTAssertEqual(input, url)
                await removeFlag.set(true)            }
        )

        try await service.saveVideo(url)
        let wasSaved = await saveFlag.get() ?? false
        let wasRemovedCalled = await removeFlag.get() ?? false
        XCTAssertTrue(wasSaved)
        XCTAssertTrue(wasRemovedCalled)
    }

    // MARK: - Error Propagation

    func test_saveImage_propagatesErrorsFromSaveHandler() async {
        struct TestError: Error {}

        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveImageHandler: { _ in throw TestError() },
            removeItem: { _ in }
        )

        await XCTAssertThrowsError(ofType: TestError.self, try await service.saveImage(UIImage()))
    }

    func test_saveVideo_doesNotCrashIfRemoveFails() async throws {
        let service = MediaLibraryService.live(
            permissionChecker: {},
            saveVideoHandler: { _ in },
            removeItem: { _ in throw NSError(domain: "test", code: 42) }
        )

        try await service.saveVideo(.mock())
    }
}
