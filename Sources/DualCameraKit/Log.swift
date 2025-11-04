import os

public enum LogCategory: String {
    case camera, session, errors, general
}

public struct DualCameraLogger {
    private static let subsystem = "DualCameraKit"

    // Unified access
    public static func log(
        _ message: String,
        category: LogCategory = .general,
        level: OSLogType = .debug
    ) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        #if targetEnvironment(simulator)
        // Always echo to console for fast feedback in Simulator
        print("[\(category.rawValue.uppercased())] \(message)")
        #endif
        logger.log(level: level, "\(message, privacy: .public)")
    }
}
