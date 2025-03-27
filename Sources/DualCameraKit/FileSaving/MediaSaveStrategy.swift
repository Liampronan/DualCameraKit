import UIKit

public enum MediaSaveStrategy<T> {
    case saveToPhotos
    case custom((T) -> Void)
}

// TODO: should both these be urls?
public typealias VideoSaveStrategy = MediaSaveStrategy<URL>
public typealias PhotoSaveStrategy = MediaSaveStrategy<UIImage>

