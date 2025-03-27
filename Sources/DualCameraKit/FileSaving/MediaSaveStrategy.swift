import UIKit

public enum MediaSaveStrategy<T, U> {
    case saveToLibrary(U)
    case custom((T) -> Void)
    
    
}

// TODO: should both these be urls?
public typealias VideoSaveStrategy = MediaSaveStrategy<URL, VideoLibraryPersisting>
public typealias PhotoSaveStrategy = MediaSaveStrategy<UIImage, PhotoLibraryPersisting>

 
extension VideoSaveStrategy {
    func save(url: URL) async throws {
        switch self {
        case .saveToLibrary(let videoLibraryService): try await videoLibraryService.saveVideo(at: url)
        case .custom(let cb): cb(url)
        }
    }
}
