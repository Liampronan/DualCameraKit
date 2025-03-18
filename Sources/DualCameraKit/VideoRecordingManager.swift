import AVFoundation
import UIKit

public protocol DualCameraVideoRecording2: Actor {
    func startVideoRecording(mode: DualCameraVideoRecordingMode, outputURL: URL?) async throws
    func stopVideoRecording() async throws -> URL
}

// A dedicated actor to handle video recording operations
actor VideoRecordingManager: DualCameraVideoRecording2 {
    // Core recording components
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    
    // Frame management
    private var pixelBufferPool: CVPixelBufferPool?
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: DisplayLinkTarget?
    private var recordingStartTime: CMTime?
    private var previousFrameTime: CMTime?
    private var frameCount: Int = 0
    
    // Recording state
    // Recording state with associated URL
    private enum RecordingState {
        case inactive
        case active(outputURL: URL)
    }
    
    private var state: RecordingState = .inactive
    private let captureMode: DualCameraCaptureMode
    //    private(set) var outputURL: URL
    
    // Configuration
    private let frameRate: Int
    //    private let dimensions: CGSize
    //    private let photoCapturer: any DualCameraPhotoCapturing
    private let photoCapturer: any DualCameraPhotoCapturing
    
    
    init(
        frameRate: Int = 30,
        captureMode: DualCameraCaptureMode,
        photoCapturer: any DualCameraPhotoCapturing
    ) {
        //        self.dimensions = dimensions
        self.frameRate = frameRate
        self.captureMode = captureMode
        self.photoCapturer = photoCapturer
    }
    
    // TODO: fix this params - either use here or move to init. consider moving to init and then maknig that consistent for protocol
    func startVideoRecording(mode: DualCameraVideoRecordingMode, outputURL: URL? = nil) async throws {
        guard case .inactive = state else {
            throw DualCameraError.recordingInProgress
        }
        
        // Generate default URL if none provided
        let actualOutputURL: URL
        if let outputURL = outputURL {
            actualOutputURL = outputURL
        } else {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
            actualOutputURL = tempDir.appendingPathComponent(fileName)
        }
        
        // Set up asset writer
        do {
            assetWriter = try AVAssetWriter(outputURL: actualOutputURL, fileType: .mp4)
        } catch {
            throw DualCameraError.recordingFailed(.assetWriterCreationFailed)
        }
        let dimensions: CGSize = await calculateDimensions(for: mode)

        // Configure video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000, // 6 Mbps
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30, // Keyframe every second at 30fps
                AVVideoAllowFrameReorderingKey: false // Reduces latency
            ]
        ]
        
        // Create video input
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = videoInput, let assetWriter = assetWriter, assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else {
            throw DualCameraError.recordingFailed(.assetWriterConfigurationFailed)
        }
        
        // Set up pixel buffer adaptor
        setupPixelBufferPool(dimensions: dimensions)
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(dimensions.width),
                kCVPixelBufferHeightKey as String: Int(dimensions.height)
            ]
        )
        
        // Start the asset writer
        guard assetWriter?.startWriting() == true else {
            throw DualCameraError.recordingFailed(.assetWriterConfigurationFailed)
        }
        
        // Initialize frame timing
        recordingStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        assetWriter?.startSession(atSourceTime: .zero)
        
        // Set up display link
        setupDisplayLink()
        
        // Update state to active with the output URL
        state = .active(outputURL: actualOutputURL)
    }
    
    private func calculateDimensions(for mode: DualCameraVideoRecordingMode) async -> CGSize {
        switch mode {
        case .screenCapture(let captureMode):
            switch captureMode {
            case .fullScreen:
                //TODO: can we remove UIScreen implicit depenedncy here
                return await MainActor.run { UIScreen.main.bounds.size }
            case .containerSize(let size):
                return size
            }
            //TODO: Fixme this shouldn't be hard coded
        case .rawCapture(let combineStreams):
            // For raw capture, default to 1080p or determine from camera capabilities
            return CGSize(width: 1920, height: 1080)
        }
    }
    
    func stopVideoRecording() async throws -> URL {
        guard case .active(let outputURL) = state else {
            throw DualCameraError.noRecordingInProgress
        }
        
        // Invalidate display link
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        
        // Finalize recording
        if let videoInput = videoInput {
            videoInput.markAsFinished()
        }
        
        if let audioInput = audioInput {
            audioInput.markAsFinished()
        }
        
        // Wait for asset writer to finish
        if let assetWriter = assetWriter {
            await withCheckedContinuation { continuation in
                assetWriter.finishWriting {
                    continuation.resume()
                }
            }
        }
        
        print("Recording completed with \(frameCount) frames")
        
        // Reset state
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        pixelBufferPool = nil
        recordingStartTime = nil
        previousFrameTime = nil
        frameCount = 0
        state = .inactive
        
        return outputURL
    }
    
    
    // Helper class to avoid retain cycles with CADisplayLink
    private class DisplayLinkTarget {
        private weak var manager: VideoRecordingManager?
        
        init(manager: VideoRecordingManager) {
            self.manager = manager
        }
        
        @objc func captureFrame() {
            guard let manager = manager else { return }
            
            Task {
                await manager.handleDisplayLinkCapture()
            }
        }
    }
    
    //    @MainActor
    private func setupDisplayLink() {
        // Create target to avoid retain cycles
        displayLinkTarget = DisplayLinkTarget(manager: self)
        
        displayLink = CADisplayLink(
            target: displayLinkTarget!,
            selector: #selector(DisplayLinkTarget.captureFrame)
        )
        
        displayLink?.preferredFramesPerSecond = frameRate
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func setupPixelBufferPool(dimensions: CGSize) {
            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 5
            ]
            
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(dimensions.width),
                kCVPixelBufferHeightKey as String: Int(dimensions.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                pixelBufferAttributes as CFDictionary,
                &pixelBufferPool
            )
        }
    
    private func handleDisplayLinkCapture() async {
        do {
            // Ensure writer is ready
            guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else {
                return
            }
            
            // Determine frame timing
            let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
            let presentationTime: CMTime
            
            if let startTime = recordingStartTime {
                presentationTime = CMTimeSubtract(currentTime, startTime)
            } else {
                presentationTime = .zero
            }
            
            // Skip if it's too soon for another frame (enforces frame rate)
            if let prevTime = previousFrameTime {
                let elapsed = CMTimeSubtract(presentationTime, prevTime)
                let targetDuration = CMTime(value: 1, timescale: Int32(frameRate))
                
                if CMTimeCompare(elapsed, targetDuration) < 0 {
                    return
                }
            }
            
            // Capture frame
            let image = try await (photoCapturer as! DualCameraPhotoCapturer).captureCurrentScreen(mode: captureMode)
            guard let buffer = image.pixelBuffer() else {
                throw DualCameraError.captureFailure(.imageCreationFailed)
            }
            
            
            guard let buffer = image.pixelBuffer() else {
                // TODO: handle error
                throw DualCameraError.notImplemented
            }
            let pixelBufferWrapper = PixelBufferWrapper(buffer: buffer)
            // Append frame to writer
            if let adaptor = pixelBufferAdaptor {
                if adaptor.append(pixelBufferWrapper.buffer, withPresentationTime: presentationTime) {
                    previousFrameTime = presentationTime
                    frameCount += 1
                }
            }
        } catch {
            print("Error capturing frame: \(error)")
        }
    }
    
}
