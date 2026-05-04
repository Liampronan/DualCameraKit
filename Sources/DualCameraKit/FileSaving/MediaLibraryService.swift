import Photos
import UIKit

// MARK: - Media Library Service

public struct MediaLibraryService: Sendable {
    public var saveImage: @Sendable (UIImage) async throws -> Void

    public init(
        saveImage: @escaping @Sendable (UIImage) async throws -> Void
    ) {
        self.saveImage = saveImage
    }
}

public extension MediaLibraryService {
    static func live(
        permissionChecker: @escaping @Sendable () async throws -> Void = Self.defaultPermissionChecker,
        saveImageHandler: @escaping @Sendable (UIImage) async throws -> Void = { image in
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    ) -> Self {
        Self(
            saveImage: { image in
                try await permissionChecker()
                try await saveImageHandler(image)
            }
        )
    }

    static func test(
        saveImage: @escaping @Sendable (UIImage) async throws -> Void = { _ in }
    ) -> Self {
        Self(saveImage: saveImage)
    }

    static var noop: Self {
        Self(
            saveImage: { _ in }
        )
    }

    static var failing: Self {
        Self(
            saveImage: { _ in
                throw MediaLibraryError.savingFailed(
                    underlyingError: NSError(
                        domain: "MediaLibraryService",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unimplemented saveImage."]
                    )
                )
            }
        )
    }

    static let defaultPermissionChecker: @Sendable () async throws -> Void = {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized, .limited:
            return
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw MediaLibraryError.permissionDenied
            }
        case .denied, .restricted:
            throw MediaLibraryError.permissionDenied
        @unknown default:
            throw MediaLibraryError.unknown
        }
    }
}

// MARK: - Error Handling

public enum MediaLibraryError: Error, LocalizedError {
    case permissionDenied
    case savingFailed(underlyingError: Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access is required to save photos."
        case .savingFailed(let error):
            return "Failed to save photo: \(error.localizedDescription)"
        case .unknown:
            return "Unknown error occurred while saving media."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please grant photo library access in Settings to save photos."
        case .savingFailed:
            return "Please try again. If the problem persists, check available storage."
        case .unknown:
            return "Please try again later."
        }
    }
}

extension MediaLibraryError: Equatable {
    public static func == (lhs: MediaLibraryError, rhs: MediaLibraryError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied, .permissionDenied),
             (.unknown, .unknown):
            return true
        case (.savingFailed, .savingFailed):
            return true
        default:
            return false
        }
    }
}
