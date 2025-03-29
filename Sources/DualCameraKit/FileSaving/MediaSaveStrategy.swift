import UIKit

// MARK: - Media Save Strategy
/// Describes how to save captured video/images.
///
/// `saveToPhotoLibrary`  involves permission grant to write to user's photo library.
///
///  `custom` opts-out of saving to user's photo library; useful for when you don't need to save to library or want to handle permission flow in a custom way.
public enum MediaSaveStrategy<Media: Sendable>: Sendable {
    case saveToMediaLibrary(@Sendable (Media) async throws -> Void)
    case custom(@Sendable (Media) async throws -> Void)

    public func save(_ media: Media) async throws {
        switch self {
        case .saveToMediaLibrary(let librarySaver):
            try await librarySaver(media)
        case .custom(let handler):
            try await handler(media)
        }
    }
}

// MARK: - Type Aliases
public typealias PhotoSaveStrategy = MediaSaveStrategy<UIImage>
public typealias VideoSaveStrategy = MediaSaveStrategy<URL>

public extension PhotoSaveStrategy {
    /// Creates a strategy that saves photos to the user's media library using the provided service.
    /// - Parameter service: The service responsible for handling photo library operations.
    /// - Returns: A configured save strategy for photos.
    static func photoLibrary(service: MediaLibraryService) -> PhotoSaveStrategy {
        .saveToMediaLibrary { [service] image in
            try await service.saveImage(image)
        }
    }
}

public extension VideoSaveStrategy {
    /// Creates a strategy that saves videos to the user's media library using the provided service.
    /// - Parameter service: The service responsible for handling photo library operations.
    /// - Returns: A configured save strategy for photos.
    static func videoLibrary(service: MediaLibraryService) -> VideoSaveStrategy {
        .saveToMediaLibrary { [service] url in
            try await service.saveVideo(url)
        }
    }
}
