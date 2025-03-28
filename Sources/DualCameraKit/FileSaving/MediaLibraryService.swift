import Photos
import UIKit

// MARK: - Media Library Service

public struct MediaLibraryService: Sendable  {
    public init() {}
    
    public func saveImage(_ image: UIImage) async throws {
        try await checkPhotoLibraryPermission()

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    public func saveVideo(at url: URL) async throws {
        try await checkPhotoLibraryPermission()

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Permission Handling

    private func checkPhotoLibraryPermission() async throws {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                throw MediaLibraryError.permissionDenied
            }
        case .denied, .restricted:
            throw MediaLibraryError.permissionDenied
        @unknown default:
            throw MediaLibraryError.unknown
        }
    }
}
//
//public class MediaLibraryService {
//    // Injected dependencies
//    private let permissionChecker: () async throws -> Void
//    private let performPhotoLibraryChanges: (@escaping () -> Void) async throws -> Void
//    private let removeFile: (URL) throws -> Void
//
//    // Default initializer for production
//    public init(
//        permissionChecker: @escaping () async throws -> Void = MediaLibraryService.defaultPermissionChecker,
//        performPhotoLibraryChanges: @escaping (@escaping () -> Void) async throws -> Void = PHPhotoLibrary.shared().performChanges,
//        removeFile: @escaping (URL) throws -> Void = FileManager.default.removeItem
//    ) {
//        self.permissionChecker = permissionChecker
//        self.performPhotoLibraryChanges = performPhotoLibraryChanges
//        self.removeFile = removeFile
//    }
//
//    public func saveImage(_ image: UIImage) async throws {
//        try await permissionChecker()
//        try await performPhotoLibraryChanges {
//            PHAssetChangeRequest.creationRequestForAsset(from: image)
//        }
//    }
//
//    public func saveVideo(at url: URL) async throws {
//        try await permissionChecker()
//        try await performPhotoLibraryChanges {
//            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
//        }
//        try? removeFile(url)
//    }
//
//    // MARK: - Default Implementations
//
//    private static func defaultPermissionChecker() async throws {
//        switch PHPhotoLibrary.authorizationStatus() {
//        case .authorized, .limited:
//            return
//        case .notDetermined:
//            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
//            guard newStatus == .authorized || newStatus == .limited else {
//                throw MediaLibraryError.permissionDenied
//            }
//        case .denied, .restricted:
//            throw MediaLibraryError.permissionDenied
//        @unknown default:
//            throw MediaLibraryError.unknown
//        }
//    }
//}


// MARK: - Error Handling

public enum MediaLibraryError: Error, LocalizedError {
    case permissionDenied
    case savingFailed(underlyingError: Error)
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access is required to save media."
        case .savingFailed(let error):
            return "Failed to save media: \(error.localizedDescription)"
        case .unknown:
            return "Unknown error occurred while saving media."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please grant photo library access in Settings to save photos and videos."
        case .savingFailed:
            return "Please try again. If the problem persists, check available storage."
        case .unknown:
            return "Please try again later."
        }
    }
}
