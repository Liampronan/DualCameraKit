import CoreGraphics
import CoreVideo
import ImageIO
import Vision

/// A single face observation in normalized Vision coordinates (`[0, 1]`, origin at bottom-left).
public struct DetectedFace: Sendable, Equatable {
    /// Normalized face bounding box in `[0, 1]` coordinate space with the origin at the bottom-left.
    public let boundingBox: CGRect
    /// Optional head roll angle in radians.
    public let rollAngleRadians: CGFloat?

    /// Creates a detected face observation.
    public init(boundingBox: CGRect, rollAngleRadians: CGFloat? = nil) {
        self.boundingBox = boundingBox
        self.rollAngleRadians = rollAngleRadians
    }
}

/// Abstracts face detection on a `CVPixelBuffer` for live inference and deterministic testing.
public protocol FaceDetectionProviding: Sendable {
    /// Detects faces in `pixelBuffer` and returns normalized bounding boxes (`[0, 1]`, origin bottom-left).
    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [DetectedFace]
}

/// Default `Vision`-backed face detector using `VNDetectFaceRectanglesRequest`.
public struct VisionFaceDetector: FaceDetectionProviding {
    /// Creates a Vision face detector.
    public init() {}

    /// Runs `VNDetectFaceRectanglesRequest` synchronously on the caller's background execution context.
    public func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [DetectedFace] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        return observations.map { observation in
            DetectedFace(
                boundingBox: observation.boundingBox,
                rollAngleRadians: observation.roll.map { CGFloat($0.doubleValue) }
            )
        }
    }
}
