import UIKit

public protocol DualCameraControllerProtocol {
    var frontCameraStream: AsyncStream<PixelBufferWrapper> { get }
    var backCameraStream: AsyncStream<PixelBufferWrapper> { get }
    func startSession() async throws
    func stopSession()
    func capturePhotoWithLayout(_ layout: CameraLayout, containerSize: CGSize) async throws -> UIImage
}

/// Central camera controller
public final class DualCameraController: DualCameraControllerProtocol {
    private let streamSource = CameraStreamSource()
    
    // Internal storage for renderers and their stream tasks.
    private var renderers: [CameraSource: CameraRenderer] = [:]
    private var streamTasks: [CameraSource: Task<Void, Never>] = [:]
    
    public init() {}
    
    public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.frontCameraStream
    }
    
    public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        streamSource.backCameraStream
    }
    
    @MainActor
    public func startSession() async throws {
        try await streamSource.startSession()
        // Optionally, auto-initialize renderers for both sources here.
        _ = getRenderer(for: .front)
        _ = getRenderer(for: .back)
    }
    
    public func stopSession() {
        streamSource.stopSession()
        cancelRendererTasks()
    }
    
    /// Creates a renderer (using MetalCameraRenderer by default).
    @MainActor
    public func createRenderer() -> CameraRenderer {
        return MetalCameraRenderer()
    }
    
    /// Returns a renderer for the specified camera source.
    /// If one does not exist yet, it is created and connected to its stream.
    @MainActor
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
    @MainActor
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
    
    public func capturePhotoWithLayout(_ layout: CameraLayout, containerSize: CGSize) async throws -> UIImage {
        // Get the current screen size (instead of hardcoding)
        guard let screenSize = await UIApplication.shared.windows.first?.bounds.size else {
            throw DualCameraError.captureFailure(.unknownDimensions)
        }
        
        // Get frames directly from renderers (which already handle aspect correction)
        guard let frontRenderer = renderers[.front],
              let backRenderer = renderers[.back] else {
            throw DualCameraError.captureFailure(.noPrimaryRenderer)
        }
        
        let frontImage = try await frontRenderer.captureCurrentFrame()
        let backImage = try await backRenderer.captureCurrentFrame()
        
        return renderImagesWithLayout(front: frontImage, back: backImage, layout: layout, screenSize: screenSize)
    }
    
    /// Gets the latest pixel buffer from a camera stream
    private func getLatestPixelBuffer(for source: CameraSource) async throws -> CVPixelBuffer {
        let stream = source == .front ? frontCameraStream : backCameraStream
        
        // Create a async/await wrapper for getting the next buffer
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                var latestBuffer: CVPixelBuffer?
                
                // Wait for the next frame (or use a small timeout)
                for await wrapper in stream {
                    latestBuffer = wrapper.buffer
                    break
                }
                
                if let buffer = latestBuffer {
                    continuation.resume(returning: buffer)
                } else {
                    continuation.resume(throwing: DualCameraError.captureFailure(.noFrameAvailable))
                }
            }
        }
    }
    
    /// Converts a CVPixelBuffer to UIImage
    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        return UIImage(cgImage: cgImage)
    }
    
    private func renderImagesWithLayout(front: UIImage, back: UIImage, layout: CameraLayout, screenSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: screenSize)
        
        return renderer.image { ctx in
            // Background fill
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: screenSize))
            
            switch layout {
            case .fullScreenWithMini(let miniCamera, let position):
                // Determine which image is main and which is PiP
                let mainImage = miniCamera == .front ? back : front
                let miniImage = miniCamera == .front ? front : back
                
                // Draw main camera fullscreen with proper aspect ratio
                drawImageAspectFill(mainImage, in: CGRect(origin: .zero, size: screenSize), context: ctx)
                
                // Calculate PiP size
                // Standard PiP width proportion from DualCameraScreen
                let pipWidthProportion: CGFloat = 150 / screenSize.width
                let pipWidth = screenSize.width * pipWidthProportion
                
                // Calculate height to maintain the mini image's aspect ratio
                let miniAspect = miniImage.size.width / miniImage.size.height
                let pipHeight = pipWidth / miniAspect
                
                // Position based on enum with padding matching the UI
                let padding: CGFloat = 16
                let pipX: CGFloat, pipY: CGFloat
                
                switch position {
                case .topLeading:
                    pipX = padding
                    pipY = padding
                case .topTrailing:
                    pipX = screenSize.width - pipWidth - padding
                    pipY = padding
                case .bottomLeading:
                    pipX = padding
                    pipY = screenSize.height - pipHeight - padding
                case .bottomTrailing:
                    pipX = screenSize.width - pipWidth - padding
                    pipY = screenSize.height - pipHeight - padding
                    // START: this is (HACKY) close to getting pip layout there.
                    // *i think* we need to account for safe area
                    //                    pipY = screenSize.height - pipHeight - 2.0 * padding
                }
                
                let pipRect = CGRect(x: pipX, y: pipY, width: pipWidth, height: pipHeight)
                
                // Draw PiP with corner radius
                let cornerRadius: CGFloat = 10
                let path = UIBezierPath(roundedRect: pipRect, cornerRadius: cornerRadius)
                ctx.cgContext.saveGState()
                ctx.cgContext.addPath(path.cgPath)
                ctx.cgContext.clip()
                
                // Draw mini image maintaining aspect ratio
                drawImageAspectFit(miniImage, in: pipRect, context: ctx)
                ctx.cgContext.restoreGState()
                
                // Draw border
                UIColor.white.setStroke()
                let borderPath = UIBezierPath(roundedRect: pipRect, cornerRadius: cornerRadius)
                borderPath.lineWidth = 2
                borderPath.stroke()
                
            case .sideBySide:
                // Draw side by side with equal width but proper aspect ratios
                let halfWidth = screenSize.width / 2
                let leftRect = CGRect(x: 0, y: 0, width: halfWidth, height: screenSize.height)
                let rightRect = CGRect(x: halfWidth, y: 0, width: halfWidth, height: screenSize.height)
                
                drawImageAspectFit(back, in: leftRect, context: ctx)
                drawImageAspectFit(front, in: rightRect, context: ctx)
                
            case .stackedVertical:
                // Draw stacked with equal height but proper aspect ratios
                let halfHeight = screenSize.height / 2
                let topRect = CGRect(x: 0, y: 0, width: screenSize.width, height: halfHeight)
                let bottomRect = CGRect(x: 0, y: halfHeight, width: screenSize.width, height: halfHeight)
                
                drawImageAspectFit(back, in: topRect, context: ctx)
                drawImageAspectFit(front, in: bottomRect, context: ctx)
            }
        }
    }
    
    // Helper function to draw an image with aspect fill (covers the entire rect, may crop)
    private func drawImageAspectFill(_ image: UIImage, in rect: CGRect, context: UIGraphicsImageRendererContext) {
        let imageSize = image.size
        let targetSize = rect.size
        
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        
        // Use the larger ratio to ensure the image fills the entire rect
        let scale = max(widthRatio, heightRatio)
        
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        // Center the image
        let drawX = rect.origin.x + (targetSize.width - scaledWidth) / 2
        let drawY = rect.origin.y + (targetSize.height - scaledHeight) / 2
        
        let drawRect = CGRect(x: drawX, y: drawY, width: scaledWidth, height: scaledHeight)
        image.draw(in: drawRect)
    }
    
    // Helper function to draw an image with aspect fit (shows the entire image, may have letterboxing)
    private func drawImageAspectFit(_ image: UIImage, in rect: CGRect, context: UIGraphicsImageRendererContext) {
        let imageSize = image.size
        let targetSize = rect.size
        
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        
        // Use the smaller ratio to ensure the entire image fits
        let scale = min(widthRatio, heightRatio)
        
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        // Center the image
        let drawX = rect.origin.x + (targetSize.width - scaledWidth) / 2
        let drawY = rect.origin.y + (targetSize.height - scaledHeight) / 2
        
        let drawRect = CGRect(x: drawX, y: drawY, width: scaledWidth, height: scaledHeight)
        image.draw(in: drawRect)
    }
    
    /// Combines photos from both renderers (for a PiP effect).
    //    public func captureCombinedPhoto() async throws -> UIImage {
    //        guard let frontRenderer = renderers[.front],
    //              let backRenderer = renderers[.back] else {
    //            throw DualCameraError.captureFailure(.noPrimaryRenderer)
    //        }
    //
    //        let backImage = try await backRenderer.captureCurrentFrame()
    //        let frontImage = try await frontRenderer.captureCurrentFrame()
    //        let size = backImage.size
    //
    //        let renderer = UIGraphicsImageRenderer(size: size)
    //        return renderer.image { ctx in
    //            // Draw full-screen back image.
    //            backImage.draw(in: CGRect(origin: .zero, size: size))
    //            // Overlay front image as picture-in-picture.
    //            let pipWidth = size.width / 3
    //            let pipHeight = size.height / 3
    //            let pipRect = CGRect(x: size.width - pipWidth - 10, y: 10, width: pipWidth, height: pipHeight)
    //            frontImage.draw(in: pipRect)
    //        }
    //    }
}

