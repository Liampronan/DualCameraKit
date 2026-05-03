import UIKit

// MARK: - Media Save Strategy
/// Describes how to save captured images.
///
/// `saveToPhotoLibrary`  involves permission grant to write to user's photo library.
///
/// `custom` opts out of saving to user's photo library; useful when callers
/// want to handle persistence and permission flow themselves.
public enum DualCameraMediaSaveStrategy<Media: Sendable>: Sendable {
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
public typealias DualCameraPhotoSaveStrategy = DualCameraMediaSaveStrategy<UIImage>

public extension DualCameraPhotoSaveStrategy {
    /// Creates a strategy that saves photos to the user's media library using the provided service.
    /// - Parameter service: The service responsible for handling photo library operations.
    /// - Returns: A configured save strategy for photos.
    static func photoLibrary(service: MediaLibraryService) -> DualCameraPhotoSaveStrategy {
        .saveToMediaLibrary { [service] image in
            try await service.saveImage(image)
        }
    }
}
