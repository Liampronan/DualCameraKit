import AVFoundation
import CoreVideo
import UIKit

public struct DualCameraCPUVideoRecorderConfig: Sendable {
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

/// Records video using CPU-intensive UIImage capture. 
public actor DualCameraCPUVideoRecorderManager: DualCameraVideoRecording {
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
    
    private var availableBuffers: [CVPixelBuffer] = []

    // queue for processing UIImage -> PixelBuffer conversion
    private let processingQueue = DispatchQueue(label: "com.dualcamera.videoprocessing", qos: .userInitiated)
    
    private enum RecordingState {
        case inactive
        case active(outputURL: URL, quality: VideoQuality)
    }
    
    private var state: RecordingState = .inactive
    // Configuration
    nonisolated private let photoCapturer: any DualCameraPhotoCapturing
    private let config: DualCameraCPUVideoRecorderConfig
    private var photoCaptureMode: DualCameraPhotoCaptureMode {
        config.mode.asPhotoCaptureMode!
    }
    
    public init(
        photoCapturer: any DualCameraPhotoCapturing,
        config: DualCameraCPUVideoRecorderConfig
    ) {
        self.photoCapturer = photoCapturer
        self.config = config
    }
    
    public func startVideoRecording() async throws {
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
                kCVPixelBufferHeightKey as String: Int(dimensions.height),
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
        DualCameraLogger.session.debug("📹 Screen recording started with DualCameraCPUVideoRecorderManager")
    }
    
    public func stopVideoRecording() async throws -> URL {
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
        
        DualCameraLogger.session.debug("Recording completed with \(self.frameCount) frames using DualCameraCPUVideoRecorderManager")
        
        resetRecordingState()
        
        return outputURL
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
    
    // Helper class to avoid retain cycles with CADisplayLink
    private class DisplayLinkTarget {
        private weak var manager: DualCameraCPUVideoRecorderManager?
        
        init(manager: DualCameraCPUVideoRecorderManager) {
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
        
        // Standard CADisplayLink setup
        let standardDisplayLink = CADisplayLink(
            target: displayLinkTarget!,
            selector: #selector(DisplayLinkTarget.captureFrame)
        )
        
        // Configure for precise frame rate control
        standardDisplayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(frameRate - 5),
            maximum: Float(frameRate),
            preferred: Float(frameRate)
        )
        
        // Set up display link
        self.displayLink = standardDisplayLink
        let runLoop = RunLoop.main
        self.displayLink?.add(to: runLoop, forMode: .common)
        self.displayLink?.add(to: runLoop, forMode: .tracking)
        DualCameraLogger.session.info("Standard display link in use")
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
    }
    
    private func handleDisplayLinkCapture() async {
        do {
            // Check that writer components are ready.
            guard let videoInput = videoInput,
                  videoInput.isReadyForMoreMediaData,
                  let adaptor = pixelBufferAdaptor else {
                return
            }
            guard case .active(_, let quality) = state else {
                throw DualCameraError.noRecordingInProgress
            }
            
            // Compute presentation time.
            let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
            guard let startTime = recordingStartTime else { return }
            let presentationTime = CMTimeSubtract(currentTime, startTime)
            
            // Adaptive frame timing.
            if let prevTime = previousFrameTime {
                let elapsed = CMTimeSubtract(presentationTime, prevTime)
                let elapsedSeconds = CMTimeGetSeconds(elapsed)
                let targetFrameDuration = 1.0 / Double(quality.frameRate)
                frameTimeAccumulator += elapsedSeconds
                if frameTimeAccumulator < targetFrameDuration { return }
                if frameTimeAccumulator > (targetFrameDuration * 2.0) {
                    let framesToSkip = Int(frameTimeAccumulator / targetFrameDuration) - 1
                    frameTimeAccumulator = 0
                    if framesToSkip > 0 { skippedFrameCount += framesToSkip }
                } else {
                    frameTimeAccumulator -= targetFrameDuration
                }
            }
            
            // Capture the screen image
            let mode = photoCaptureMode
            let image = try await photoCapturer.captureCurrentScreen(mode: mode)
            
            // Offload UIImage -> pixel buffer conversion to a background queue.
            let pixelBuffer = await withCheckedContinuation { continuation in
                processingQueue.async {
                    let buffer = image.pixelBuffer()
                    continuation.resume(returning: buffer)
                }
            }
            guard let buffer = pixelBuffer else {
                throw DualCameraError.captureFailure(.imageCreationFailed)
            }
            
            // Append the converted buffer.
            if adaptor.append(buffer, withPresentationTime: presentationTime) {
                previousFrameTime = presentationTime
                frameCount += 1
            }
        } catch {
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
    
    private func resetRecordingState() {
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
    }
}
