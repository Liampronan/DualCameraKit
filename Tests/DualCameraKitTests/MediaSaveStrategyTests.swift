import XCTest
@testable import DualCameraKit

final class MediaSaveStrategyTests: XCTestCase {
    func test_customPhotoStrategy() async throws {
        let imageBox = TestBox<UIImage>()
        let testImage = UIImage()

        let strategy = DualCameraPhotoSaveStrategy.custom { image in
            await imageBox.set(image)
        }

        try await strategy.save(testImage)

        let savedImage = await imageBox.get()
        XCTAssertTrue(savedImage === testImage)
    }

    func test_mediaLibraryPhotoStrategy() async throws {
        let imageBox = TestBox<UIImage>()
        let testImage = UIImage()
        let mock = MediaLibraryService.test(saveImage: { image in
            await imageBox.set(image)
        })

        let strategy = DualCameraPhotoSaveStrategy.saveToMediaLibrary(mock.saveImage)
        try await strategy.save(testImage)
        let savedImage = await imageBox.get()
        XCTAssertTrue(savedImage === testImage)
    }

    func test_mediaLibraryStrategy_unimplementedFails() async {
        let strategy = DualCameraPhotoSaveStrategy.saveToMediaLibrary(MediaLibraryService.failing.saveImage)
        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await strategy.save(UIImage()))
    }

}
