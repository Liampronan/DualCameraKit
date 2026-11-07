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

    func test_savePhotoSet_failsIfPermissionDeniedWithoutInvokingHandler() async {
        let denied: @Sendable () async throws -> Void = {
            throw MediaLibraryError.permissionDenied
        }
        let photoSet = DualCameraCapturedPhotoSet(
            composed: UIImage(),
            frontRaw: UIImage(),
            backRaw: UIImage()
        )

        let service = MediaLibraryService.live(
            permissionChecker: denied,
            savePhotoSetHandler: { _ in XCTFail("Should not attempt savePhotoSet") }
        )

        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await service.savePhotoSet(photoSet))
    }

    func test_savePhotoSet_checksPermissionOnceAndInvokesPhotoSetHandler() async throws {
        let permissionCount = TestBox<Int>()
        await permissionCount.set(0)
        let savedSetBox = TestBox<DualCameraCapturedPhotoSet>()
        let expectedSet = DualCameraCapturedPhotoSet(
            composed: UIImage(),
            frontRaw: UIImage(),
            backRaw: UIImage()
        )

        let service = MediaLibraryService.live(
            permissionChecker: {
                let current = await permissionCount.get() ?? 0
                await permissionCount.set(current + 1)
            },
            savePhotoSetHandler: { photoSet in
                await savedSetBox.set(photoSet)
            }
        )

        try await service.savePhotoSet(expectedSet)

        let finalPermissionCount = await permissionCount.get()
        let savedSet = await savedSetBox.get()
        XCTAssertEqual(finalPermissionCount, 1)
        XCTAssertEqual(savedSet, expectedSet)
    }

    func test_initWithSaveImageOnly_defaultsSavePhotoSetToThreeSaveImageCalls() async throws {
        let savedImages = TestBox<[UIImage]>()
        await savedImages.set([])
        let expectedSet = DualCameraCapturedPhotoSet(
            composed: UIImage(),
            frontRaw: UIImage(),
            backRaw: UIImage()
        )

        let service = MediaLibraryService { image in
            var current = await savedImages.get() ?? []
            current.append(image)
            await savedImages.set(current)
        }

        try await service.savePhotoSet(expectedSet)

        let saved = await savedImages.get()
        let images = try XCTUnwrap(saved)
        XCTAssertEqual(images.count, 3)
        XCTAssertTrue(images[0] === expectedSet.composed)
        XCTAssertTrue(images[1] === expectedSet.frontRaw)
        XCTAssertTrue(images[2] === expectedSet.backRaw)
    }

}
