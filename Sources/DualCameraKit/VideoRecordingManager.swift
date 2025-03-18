import AVFoundation
import CoreVideo
import UIKit

public struct DualCameraVideoRecordingConfig: Sendable {
    public let mode: DualCameraVideoRecordingMode
    public let quality: VideoQuality
    public let outputURL: URL?
    
    public init(
        mode: DualCameraVideoRecordingMode,
        quality: VideoQuality = .high,
        outputURL: URL? = nil
    ) {
        self.mode = mode
        self.quality = quality
        self.outputURL = outputURL
    }
}

public protocol DualCameraVideoRecording2: Actor {
    func startVideoRecording(config: DualCameraVideoRecordingConfig) async throws
    func stopVideoRecording() async throws -> URL
}

// Convenience extension if you want both approaches
public extension DualCameraVideoRecording2 {
    func startVideoRecording(
        mode: DualCameraVideoRecordingMode,
        quality: VideoQuality = .high,
        outputURL: URL? = nil
    ) async throws {
        let config = DualCameraVideoRecordingConfig(mode: mode, quality: quality, outputURL: outputURL)
        try await startVideoRecording(config: config)
    }
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
    private var skippedFrameCount: Int = 0
    private var frameTimeAccumulator: Double = 0.0
    
    private enum RecordingState {
        case inactive
        case active(outputURL: URL, quality: VideoQuality)
    }
    
    private var state: RecordingState = .inactive
    // Configuration
    private let photoCapturer: any DualCameraPhotoCapturing
    
    init(
        photoCapturer: any DualCameraPhotoCapturing
    ) {
        self.photoCapturer = photoCapturer
    }
    
    // TODO: fix this params - either use here or move to init. consider moving to init and then maknig that consistent for protocol
    func startVideoRecording(config: DualCameraVideoRecordingConfig) async throws {
        guard case .inactive = state else {
            throw DualCameraError.recordingInProgress
        }
        // default to high quality
        let quality = config.quality
        let bitrate = quality.bitrate
        let frameRate = quality.frameRate
        let mode = config.mode
        
        // Generate default URL if none provided
        let outputURL = configure(outputURL: config.outputURL)
        
        // Set up asset writer
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw DualCameraError.recordingFailed(.assetWriterCreationFailed)
        }
        let dimensions: CGSize = try await calculateDimensions(for: mode)

        let videoSettings = VideoRecorderSettingsFactory.createEncodingSettings(
            quality: quality,
            dimensions: dimensions
        )
        
        // Create video input
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = videoInput, let assetWriter = assetWriter, assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else {
            throw DualCameraError.recordingFailed(.assetWriterConfigurationFailed)
        }
        
        try setupPixelBufferPool(dimensions: dimensions)
        
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
        
        setupDisplayLink(frameRate: frameRate)
        
        state = .active(outputURL: outputURL, quality: quality)
    }
    
    private func calculateDimensions(for mode: DualCameraVideoRecordingMode) async throws -> CGSize {
        var rawSize: CGSize
        
        // Get base dimensions
        switch mode {
        case .screenCapture(let captureMode):
            switch captureMode {
            case .fullScreen:
                rawSize = await MainActor.run { UIScreen.main.bounds.size }
            case .containerSize(let size):
                rawSize = size
            }
            
        case .rawCapture:
            throw DualCameraError.notImplemented
        }
        
        // Apply resolution scaling to improve performance
        // Scale down to 720p-equivalent for smoother recording
        let maxDimension: CGFloat = 1280 // 720p max (16:9 ratio)
        
        if rawSize.width > maxDimension || rawSize.height > maxDimension {
            let aspectRatio = rawSize.width / rawSize.height
            
            if aspectRatio > 1 {
                // Landscape orientation
                let newWidth = min(rawSize.width, maxDimension)
                let newHeight = newWidth / aspectRatio
                rawSize = CGSize(width: newWidth, height: newHeight)
            } else {
                // Portrait orientation
                let newHeight = min(rawSize.height, maxDimension)
                let newWidth = newHeight * aspectRatio
                rawSize = CGSize(width: newWidth, height: newHeight)
            }
        }
        
        // Round dimensions to even numbers (required for some video encoders)
        let width = 2 * Int(rawSize.width / 2)
        let height = 2 * Int(rawSize.height / 2)
        
        return CGSize(width: width, height: height)
    }
    
    func stopVideoRecording() async throws -> URL {
        guard case .active(let outputURL, _) = state else {
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
        // TODO: move me to logger
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
    
    private func setupDisplayLink(frameRate: Int) {
        // Create target to avoid retain cycles
        displayLinkTarget = DisplayLinkTarget(manager: self)
        
        // Create and configure display link with optimal settings for iOS 18+
        displayLink = CADisplayLink(
            target: displayLinkTarget!,
            selector: #selector(DisplayLinkTarget.captureFrame)
        )
        
        // Configure for precise frame rate control
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(frameRate - 5),
            maximum: Float(frameRate),
            preferred: Float(frameRate)
        )
        
        // Add to multiple run loop modes for consistent timing during interactions
        let runLoop = RunLoop.main
        displayLink?.add(to: runLoop, forMode: .common)
        displayLink?.add(to: runLoop, forMode: .tracking)
        
        // Use Metal display link for better GPU synchronization if available
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            do {
                // TODO: ensure this is working
//                let _ = try displayLink
                print("Using Metal-optimized display link for recording")
            } catch {
                print("Standard display link in use: \(error.localizedDescription)")
            }
        }
    }
    
    /// Create an optimized pixel buffer pool for more efficient memory use and better performance
    private func setupPixelBufferPool(dimensions: CGSize) throws {
        let bufferCount = 8
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: bufferCount,
            kCVPixelBufferPoolMaximumBufferAgeKey as String: 1000 // 1 second maximum buffer age in milliseconds
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(dimensions.width),
            kCVPixelBufferHeightKey as String: Int(dimensions.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:], // IOSurface for better GPU/CPU sharing
            kCVPixelBufferMetalCompatibilityKey as String: true   // Enable Metal compatibility
        ]
        
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )
        
        // Check status and throw error if pool creation failed
        guard status == kCVReturnSuccess, let pool = pixelBufferPool else {
            DualCameraLogger.errors.error("Failed to create pixel buffer pool: \(status)")
            throw DualCameraError.recordingFailed(.pixelBufferPoolCreationFailed)
        }
        
        // Pre-allocate buffers in the pool to avoid allocation during recording
        var pixelBuffers = [CVPixelBuffer?](repeating: nil, count: bufferCount)
        
        // Create and immediately release buffers to warm up the pool
        for i in 0..<bufferCount {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            
            if status == kCVReturnSuccess {
                pixelBuffers[i] = pixelBuffer
            } else {
                DualCameraLogger.errors.error("Failed to pre-allocate pixel buffer \(i): \(status)")
            }
        }
    }
    
    private func handleDisplayLinkCapture() async {
        do {
            // Ensure writer is ready - exit early if not
            guard let videoInput = videoInput, 
                  videoInput.isReadyForMoreMediaData,
                  let adaptor = pixelBufferAdaptor else {
                // TODO: add error
                return
            }
            
            guard case .active(_, let quality) = state else {
                throw DualCameraError.noRecordingInProgress
            }
            
            // Get precise timing
            let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
            guard let startTime = recordingStartTime else {
                // TODO: add error
                return
            }
            
            let presentationTime = CMTimeSubtract(currentTime, startTime)
            
            // Advanced frame timing with adaptive rate control
            if let prevTime = previousFrameTime {
                let elapsed = CMTimeSubtract(presentationTime, prevTime)
                let elapsedSeconds = CMTimeGetSeconds(elapsed)
                let targetFrameDuration = 1.0 / Double(quality.frameRate)
                
                // Update timing accumulator for smoother frame pacing
                frameTimeAccumulator += elapsedSeconds
                
                // Apply dynamic frame skip based on system load
                if frameTimeAccumulator < targetFrameDuration {
                    // Too early for next frame
                    return
                }
                
                // Detect if we're falling behind (system under load)
                if frameTimeAccumulator > (targetFrameDuration * 2.0) {
                    // System is struggling - implement frame dropping to maintain timing
                    let framesToSkip = Int(frameTimeAccumulator / targetFrameDuration) - 1
                    frameTimeAccumulator = 0 // Reset accumulator after skip
                    
                    if framesToSkip > 0 {
                        skippedFrameCount += framesToSkip
                        // Performance logging removed
                    }
                } else {
                    // Normal timing - consume one frame duration
                    frameTimeAccumulator -= targetFrameDuration
                }
            }
            // TODO: fixme cast; sending
            let image = try await (photoCapturer as! DualCameraPhotoCapturer).captureCurrentScreen()
            
            // Convert to pixel buffer efficiently
            guard let buffer = image.pixelBuffer() else {
                throw DualCameraError.captureFailure(.imageCreationFailed)
            }
            
            // Create wrapper and append to writer
            let pixelBufferWrapper = PixelBufferWrapper(buffer: buffer)
            
            if adaptor.append(pixelBufferWrapper.buffer, withPresentationTime: presentationTime) {
                previousFrameTime = presentationTime
                frameCount += 1
            }
            // Error logging removed for performance
        } catch {
            // Minimized error handling for performance
            skippedFrameCount += 1
        }
    }
    
    private func configure(outputURL: URL?) -> URL {
        if let outputURL {
            return outputURL
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
        return tempDir.appendingPathComponent(fileName)
    }
}
