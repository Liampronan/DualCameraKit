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
        XCTAssertEqual(savedImage, testImage)
    }
    
    func test_customVideoStrategy() async throws {
        let urlBox = TestBox<URL>()
        let testUrl = URL.mock()
        
        let strategy = DualCameraVideoSaveStrategy.custom { url in
            await urlBox.set(url)
        }

        try await strategy.save(testUrl)
        
        let savedURL = await urlBox.get()
        XCTAssertEqual(savedURL, testUrl)
    }
    
    func test_mediaLibraryVideoStrategy() async throws {
        let urlBox = TestBox<URL>()
        let testUrl = URL.mock()
        let mock = MediaLibraryService.test(saveVideo:  { url in
            await urlBox.set(url)
        })
        
        let strategy = DualCameraVideoSaveStrategy.saveToMediaLibrary(mock.saveVideo)
        try await strategy.save(testUrl)
        let savedUrl = await urlBox.get()
        XCTAssertEqual(savedUrl, testUrl)
    }
    
    func test_mediaLibraryPhotoStrategy() async throws {
        let imageBox = TestBox<UIImage>()
        let testImage = UIImage()
        let mock = MediaLibraryService.test(saveImage:  { image in
            await imageBox.set(image)
        })
        
        let strategy = DualCameraPhotoSaveStrategy.saveToMediaLibrary(mock.saveImage)
        try await strategy.save(testImage)
        let savedImage = await imageBox.get()
        XCTAssertEqual(savedImage, testImage)
    }
    
    func test_mediaLibraryStrategy_unimplementedFails() async {
        let strategy = DualCameraPhotoSaveStrategy.saveToMediaLibrary(MediaLibraryService.failing.saveImage)
        await XCTAssertThrowsError(ofType: MediaLibraryError.self, try await strategy.save(UIImage()) )
    }


}
