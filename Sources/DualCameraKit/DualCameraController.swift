import AVFoundation
import SwiftUI
import UIKit

@MainActor
public protocol DualCameraControllerProtocol {
    var frontCameraStream: AsyncStream<PixelBufferWrapper> { get }
    var backCameraStream: AsyncStream<PixelBufferWrapper> { get }
    func startSession() async throws
    func stopSession()
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage)
    func captureCurrentScreen(mode: DualCameraCaptureMode) async throws -> UIImage
    func startVideoRecording(mode: DualCameraVideoRecordingMode, outputURL: URL) async throws
    func stopVideoRecording() async throws -> URL
    var isRecording: Bool { get }
}

public extension DualCameraControllerProtocol {
    func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        try await captureCurrentScreen(mode: mode)
    }
}

public enum DualCameraCaptureMode {
    case fullScreen
    case containerSize(CGSize)
}

/// How video recording should be performed
public enum DualCameraVideoRecordingMode {
    /// Records what is displayed on screen (the composed view)
    case screenCapture(DualCameraCaptureMode = .fullScreen)
    
    /// Records directly from camera feeds
    case rawCapture(combineStreams: Bool = true)
}

@MainActor
public final class DualCameraController: DualCameraControllerProtocol {
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
    private var renderers: [CameraSource: CameraRenderer] = [:]
    private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    // MARK: - Video Recording Properties
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var recordingStartTime: CMTime?
    private var currentRecordingURL: URL?
    private var recordingMode: DualCameraVideoRecordingMode?
    private var recordingTask: Task<Void, Error>?
    
    /// Whether recording is currently in progress
    public var isRecording: Bool {
        return recordingTask != nil
    }
    
    public init() {}
    
    nonisolated public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.frontCameraStream
    }
    
    nonisolated public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.backCameraStream
    }
    
    public func startSession() async throws {
        try await streamSource.startSession()
        
        // Auto-initialize renderers
        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }
    
    public func stopSession() {
        streamSource.stopSession()
        cancelRendererTasks()
    }
    
    /// Creates a renderer (using MetalCameraRenderer by default).
    public func createRenderer() -> CameraRenderer {
        return MetalCameraRenderer()
    }
    
    /// Returns a renderer for the specified camera source.
    /// If one does not exist yet, it is created and connected to its stream.
    public func getRenderer(for source: CameraSource) -> CameraRenderer {
        if let renderer = renderers[source] {
            return renderer
        }
        
        let newRenderer = createRenderer()
        renderers[source] = newRenderer
        connectStream(for: source, renderer: newRenderer)
        return newRenderer
    }
    
    /// Connects the appropriate camera stream to the given renderer.
    private func connectStream(for source: CameraSource, renderer: CameraRenderer) {
        let stream: AsyncStream<PixelBufferWrapper> = source == .front ? frontCameraStream : backCameraStream
        // Create a task that forwards frames from the stream to the renderer.
        let task = Task {
            for await buffer in stream {
                if Task.isCancelled { break }
                await renderer.update(with: buffer.buffer)
            }
        }
        streamTasks[source] = task
    }
    
    /// Cancels all active stream tasks.
    private func cancelRendererTasks() {
        for task in streamTasks.values {
            task.cancel()
        }
        streamTasks.removeAll()
    }
    
    /// Captures raw photos from both cameras without any compositing
    public func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        guard let frontRenderer = renderers[.front],
              let backRenderer = renderers[.back] else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        // Capture front camera image
        let frontImage = try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<UIImage, Error>) in
            Task {
                do {
                    let image = try await frontRenderer.captureCurrentFrame()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Capture back camera image
        let backImage = try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<UIImage, Error>) in
            Task {
                do {
                    let image = try await backRenderer.captureCurrentFrame()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return (front: frontImage, back: backImage)
    }

    /// Captures the current screen content.
    public func captureCurrentScreen(mode: DualCameraCaptureMode = .fullScreen) async throws -> UIImage {
        // Give SwiftUI a moment to fully render
        try await Task.sleep(for: .milliseconds(50))
        
        // First try to find the app's key window (works with both UIKit and SwiftUI)
        guard let keyWindow = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }),
                let windowScene = keyWindow.windowScene else {
            throw DualCameraError.captureFailure(.screenCaptureUnavailable)
        }
        
        // Get scene size (full screen including safe areas)
        let fullScreenSize = windowScene.screen.bounds.size
        
        switch mode {
        case .fullScreen:
            // Use full screen size for rendering
            let renderer = UIGraphicsImageRenderer(size: fullScreenSize)
            let capturedImage = renderer.image { _ in
                keyWindow.drawHierarchy(in: CGRect(origin: .zero, size: fullScreenSize), afterScreenUpdates: true)
            }
            return capturedImage
            
        case .containerSize(let size):
            guard !size.width.isZero && !size.height.isZero else {
                throw DualCameraError.captureFailure(.unknownDimensions)
            }
            
            // Use the container size for rendering
            let renderer = UIGraphicsImageRenderer(size: size)
            let capturedImage = renderer.image { context in
                // Calculate scaling to make the full screen content fit within the container size
                let scaleX = size.width / fullScreenSize.width
                let scaleY = size.height / fullScreenSize.height
                let scale = min(scaleX, scaleY) // Use min to fit the entire screen
                
                // Apply scaling
                context.cgContext.scaleBy(x: scale, y: scale)
                
                // Draw the hierarchy scaled to fit
                keyWindow.drawHierarchy(in: CGRect(origin: .zero, size: CGSize(
                    width: fullScreenSize.width,
                    height: fullScreenSize.height
                )), afterScreenUpdates: true)
            }
            return capturedImage
        }
    }
}

/// Video recording capabilities for DualCameraController
extension DualCameraController {
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
            let frameInterval: TimeInterval = 1.0 / 30.0 // 30 fps
            
            while !Task.isCancelled {
                // Capture the current screen
                let capturedImage = try await captureCurrentScreen(mode: mode)
                
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


// MARK: - UIImage Extension for Video Recording
extension UIImage {
    /// Converts UIImage to CVPixelBuffer for video recording
    func pixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        if let context = context {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            
            UIGraphicsPushContext(context)
            draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
        }
        
        return buffer
    }
}
