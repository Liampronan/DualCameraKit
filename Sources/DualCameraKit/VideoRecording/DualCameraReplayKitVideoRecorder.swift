import Foundation
import ReplayKit

public struct DualCameraReplayKitVideoRecorderConfig: Sendable, Equatable {
    let outputURL: URL?
    
    public init(outputURL: URL? = nil) {
        self.outputURL = outputURL
    }
}

/// Uses ReplayKit which smoothly captures full screen content BUT requires user to accept permission each time they start video.
public actor DualCameraReplayKitVideoRecorder: DualCameraVideoRecording {
    private var recordingStartTime: CMTime?
    
    private var state: RecordingState = .inactive
    private var config: DualCameraReplayKitVideoRecorderConfig
    
    public init(config: DualCameraReplayKitVideoRecorderConfig?) {
        self.config = config ?? DualCameraReplayKitVideoRecorderConfig()
    }
    
    private enum RecordingState: Equatable {
        case inactive
        case active(outputURL: URL)
        
        var isActive: Bool {
            if case .active(_) = self { return true }
            return false
        }
    }
    
    /// Starts video recording with ReplayKit
    public func startVideoRecording() async throws {
        let recorder = RPScreenRecorder.shared()
        
        guard case .inactive = state else {
            throw DualCameraError.recordingInProgress
        }
        
        let outputURL = configure(outputURL: config.outputURL)
        
        try await recorder.startRecording()
        state = .active(outputURL: outputURL)
        DualCameraLogger.session.debug("📹 Screen recording started with ReplayKit")
    }
    
    /// Stops an ongoing video recording and returns the URL of the recorded file
    public func stopVideoRecording() async throws -> URL {
        let recorder = RPScreenRecorder.shared()
        
        DualCameraLogger.session.debug("📹 Screen recording stopped with ReplayKit")
        
        guard case .active(let outputURL) = state else {
            throw DualCameraError.noRecordingInProgress
        }
        
        // Create a temporary URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        try await recorder.stopRecording(withOutput: tempURL)
        
        // Copy to final destination
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        try FileManager.default.copyItem(at: tempURL, to: outputURL)
        try? FileManager.default.removeItem(at: tempURL)
        
        return outputURL
    }
    
    public var isCurrentlyRecording: Bool { state.isActive }
    
    private func configure(outputURL: URL?) -> URL {
        if let outputURL {
            return outputURL
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
        return tempDir.appendingPathComponent(fileName)
    }
}
