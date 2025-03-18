import Foundation
import ReplayKit

@MainActor public protocol DualCameraVideoRecording {
    func startVideoRecording(mode: DualCameraVideoRecordingMode, outputURL: URL) async throws
    func stopVideoRecording() async throws -> URL
}

/// How video recording should be performed
public enum DualCameraVideoRecordingMode: Sendable {
    /// Records what is displayed on screen (the composed view)
    case screenCapture(DualCameraCaptureMode = .fullScreen)
    
    /// Records directly from camera feeds
    case rawCapture(combineStreams: Bool = true)
}

/// Uses ReplayKit which smoothly captures full screen content BUT requires user to accept permission each time they start video.
@MainActor
public final class ReplayKitVideoRecorder: DualCameraVideoRecording {
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
        // TODO: move this to logger 
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

/// This video recorder is a WIP. It captures video by sequentially capturing photos as rendered on screen - thus not great quality and subpar perf because we are relying on cpu not gpu here.
@MainActor
public final class CPUIntensiveVideoRecorder: DualCameraVideoRecording {
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var recordingStartTime: CMTime?
    private var currentRecordingURL: URL?
    private var recordingMode: DualCameraVideoRecordingMode?
    private var recordingTask: Task<Void, Error>?
    weak private var photoCapturer: (DualCameraPhotoCapturing)?
    
    public init(photoCapturer: DualCameraPhotoCapturing) {
        self.photoCapturer = photoCapturer
    }
    
    /// Whether recording is currently in progress
    public var isRecording: Bool {
        return recordingTask != nil
    }
    
    // MARK: - Public Methods
    
    /// Starts video recording with the specified mode
    public func startVideoRecording(mode: DualCameraVideoRecordingMode = .screenCapture(), outputURL: URL) async throws {
        if isRecording {
            throw DualCameraError.recordingInProgress
        }
        
        // Store recording parameters
        recordingMode = mode
        currentRecordingURL = outputURL
        
        // Set up recording based on mode
        switch mode {
        case .screenCapture(let captureMode):
            try await setupScreenRecording(mode: captureMode, outputURL: outputURL)
            
        case .rawCapture:
            // Raw capture is not implemented for now
            throw DualCameraError.notImplemented
        }
    }
    
    /// Stops an ongoing video recording
    public func stopVideoRecording() async throws -> URL {
        guard isRecording, let recordingTask = self.recordingTask else {
            throw DualCameraError.noRecordingInProgress
        }
        
        // Cancel recording task
        recordingTask.cancel()
        
        // Wait for recording to complete
        do {
            try await recordingTask.value
        } catch {
            // If the error is just cancellation, we can ignore it
            if !(error is CancellationError) {
                throw error
            }
        }
        
        // Reset recording state
        self.recordingTask = nil
        self.recordingMode = nil
        
        // Finalize recording
        try await finalizeRecording()
        
        guard let outputURL = currentRecordingURL else {
            throw DualCameraError.captureFailure(.imageCreationFailed)
        }
        
        return outputURL
    }
    
    // MARK: - Private Methods - Screen Recording
    
    /// Sets up screen-based recording
    private func setupScreenRecording(mode: DualCameraCaptureMode, outputURL: URL) async throws {
        // Create AVAssetWriter for the output file
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw DualCameraError.recordingFailed(.assetWriterCreationFailed)
        }
        
        // Determine recording dimensions based on the capture mode
        let dimensions: CGSize
        switch mode {
        case .fullScreen:
            dimensions = UIScreen.main.bounds.size
        case .containerSize(let size):
            dimensions = size
        }
        
        // Configure video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height
        ]
        
        // Create and add asset writer input
        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterVideoInput?.expectsMediaDataInRealTime = true
        
        if let assetWriterVideoInput = assetWriterVideoInput,
           let assetWriter = assetWriter,
           assetWriter.canAdd(assetWriterVideoInput) {
            assetWriter.add(assetWriterVideoInput)
        } else {
            throw DualCameraError.recordingFailed(.assetWriterConfigurationFailed)
        }
        
        // Set up pixel buffer adaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: dimensions.width,
            kCVPixelBufferHeightKey as String: dimensions.height
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterVideoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        // Start writing
        if assetWriter?.startWriting() != true {
            throw DualCameraError.recordingFailed(.assetWriterConfigurationFailed)
        }
        
        assetWriter?.startSession(atSourceTime: CMTime.zero)
        recordingStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        
        // Create a task to periodically capture the screen and write frames
        recordingTask = Task {
            // 30 fps - from testing on iPhone 15, this jitters at 60 FPS, likely due too much cpu work; part of upcoming refactor should address this
            // START: should this be dynamic based on frame
            let frameInterval: TimeInterval = 1.0 / 30.0
            guard let photoCapturer else {
                throw DualCameraError.recordingFailed(.noPhotoCapturerAvailable) 
                return
            }
            while !Task.isCancelled {
                // Capture the current screen
                let capturedImage = try await photoCapturer.captureCurrentScreen(mode: mode)
                
                // Convert UIImage to CVPixelBuffer
                if let pixelBuffer = capturedImage.pixelBuffer(),
                   let adaptor = pixelBufferAdaptor,
                   let input = assetWriterVideoInput,
                   input.isReadyForMoreMediaData {
                    
                    // Calculate presentation time
                    let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
                    let presentationTime = CMTimeSubtract(currentTime, recordingStartTime ?? CMTime.zero)
                    
                    // Append pixel buffer
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }
                
                // Wait for next frame
                try await Task.sleep(for: .seconds(frameInterval))
            }
        }
    }
    
    /// Finalizes the recording by stopping the asset writer
    private func finalizeRecording() async throws {
        // Create local copies to avoid data races
        guard let localAssetWriter = assetWriter else {
            throw DualCameraError.noRecordingInProgress
        }
        
        let localAssetWriterVideoInput = assetWriterVideoInput
        
        // If the asset writer is still writing, finish writing
        if localAssetWriter.status == .writing {
            // Wait for any remaining frames to be written
            if let videoInput = localAssetWriterVideoInput {
                // Only wait for a reasonable amount of time to avoid deadlocks
                let maxWaitTime = Date().addingTimeInterval(1.0) // 1 second timeout
                
                while videoInput.isReadyForMoreMediaData && Date() < maxWaitTime {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                
                // Mark video input as finished
                videoInput.markAsFinished()
            }
            
            // Finish writing asynchronously
            // Using an actor to safely handle the async finishWriting operation
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Task {
                    await localAssetWriter.finishWriting()
                    continuation.resume()
                }
            }
        }
        
        // Reset asset writer state - only access self properties at the end
        // to avoid data races during the async operations above
        self.assetWriter = nil
        self.assetWriterVideoInput = nil
        self.pixelBufferAdaptor = nil
        self.recordingStartTime = nil
    }
}
