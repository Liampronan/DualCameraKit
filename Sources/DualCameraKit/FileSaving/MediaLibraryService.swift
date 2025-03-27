import Photos
import UIKit

public protocol PhotoLibraryPersisting {
    func saveImage(_ image: UIImage) async throws
}

public protocol VideoLibraryPersisting {
    func saveVideo(at url: URL) async throws
}

public protocol MediaLibraryPersiting: PhotoLibraryPersisting & VideoLibraryPersisting { }

public class MediaLibraryService: MediaLibraryPersiting {
    public init() {}
    
    // MARK: - Public API
    
    /// Saves an image to the photo library, handling permissions
    public func saveImage(_ image: UIImage) async throws {
        // Check permissions first
        try await checkPhotoLibraryPermission()
        
        // Save the image using modern async/await
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    
    /// Saves a video to the photo library, handling permissions
    public func saveVideo(at url: URL) async throws {
        // Check permissions first
        try await checkPhotoLibraryPermission()
        
        // Save the video using modern async/await
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
        
        // Clean up temp file after successful save
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Permission Handling
    
    private func checkPhotoLibraryPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            return // Permission granted
            
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus != .authorized && newStatus != .limited {
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
