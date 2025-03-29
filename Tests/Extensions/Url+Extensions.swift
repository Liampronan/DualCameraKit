import Foundation

extension URL {
    static func mock() -> URL {
        return URL(fileURLWithPath: "/a/directory/path")
    }
}
