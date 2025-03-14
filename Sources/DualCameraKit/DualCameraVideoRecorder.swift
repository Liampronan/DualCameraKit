import Foundation
import ReplayKit

@MainActor public protocol DualCameraVideoRecorder {
    func startVideoRecording(mode: DualCameraVideoRecordingMode, outputURL: URL) async throws
    func stopVideoRecording() async throws -> URL
}

@MainActor
public final class ReplayKitVideoRecorder: DualCameraVideoRecorder {
    private var recordingStartTime: CMTime?
    private var currentRecordingURL: URL?
    private var recordingMode: DualCameraVideoRecordingMode?
    
    public init() { }
    
    /// Starts video recording with ReplayKit
    public func startVideoRecording(mode: DualCameraVideoRecordingMode = .screenCapture(), outputURL: URL) async throws {
        let recorder = RPScreenRecorder.shared()
        
        if recorder.isRecording {
            throw DualCameraError.recordingInProgress
        }
        
        // Store recording parameters
        recordingMode = mode
        currentRecordingURL = outputURL
        
        // Start the ReplayKit recording
        try await recorder.startRecording()
        
        // Log the start of recording
        print("📹 Screen recording started with ReplayKit")
    }
    
    /// Stops an ongoing video recording and returns the URL of the recorded file
    public func stopVideoRecording() async throws -> URL {
        let recorder = RPScreenRecorder.shared()
        
        guard recorder.isRecording, let outputURL = currentRecordingURL else {
            throw DualCameraError.noRecordingInProgress
        }
        
        // Create a temporary URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Use the async/await version of stopRecording
        try await recorder.stopRecording(withOutput: tempURL)
        
        // Copy to final destination
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        try FileManager.default.copyItem(at: tempURL, to: outputURL)
        try? FileManager.default.removeItem(at: tempURL)
        
        recordingMode = nil
        return outputURL
    }
}
