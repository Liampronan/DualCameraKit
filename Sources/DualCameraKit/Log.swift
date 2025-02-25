import os

/// Centralized logging for DualCameraKit
internal struct DualCameraLogger {
    private static let subsystem = "DualCameraKit"
    
    static let camera = Logger(subsystem: subsystem, category: "Camera")
    static let session = Logger(subsystem: subsystem, category: "Session")
    static let errors = Logger(subsystem: subsystem, category: "Errors")
}
