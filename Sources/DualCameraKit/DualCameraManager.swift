import AVFoundation

public protocol DualCameraManagerProtocol {
    var frontCameraStream: AsyncStream<CVPixelBuffer> { get }
    var backCameraStream: AsyncStream<CVPixelBuffer> { get }
    func startSession() async throws
    func stopSession()
}

struct DualCameraConstants {
    static let processingQueueFront = DispatchQueue(label: "DualCameraKit.processing.front", qos: .userInitiated)
    static let processingQueueBack = DispatchQueue(label: "DualCameraKit.processing.back", qos: .userInitiated)
    static let sessionQueue = DispatchQueue(label: "DualCameraKit.session.queue")
}

/// `DualCameraManager` provides a unified interface for capturing
/// video streams from the front and back cameras simultaneously.
/// It ensures only one active session is running at a time.
public class DualCameraManager: NSObject {
    public var frontCameraStream: AsyncStream<PixelBufferWrapper>!
    public var backCameraStream: AsyncStream<PixelBufferWrapper>!
    private var frontCameraContinuation: AsyncStream<PixelBufferWrapper>.Continuation?
    private var backCameraContinuation: AsyncStream<PixelBufferWrapper>.Continuation?
    
    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DualCameraConstants.sessionQueue

    private var frontCameraInput: AVCaptureDeviceInput?
    private var backCameraInput: AVCaptureDeviceInput?
    
    private var frontCameraOutput: AVCaptureVideoDataOutput?
    private var backCameraOutput: AVCaptureVideoDataOutput?

    
    /// Because we are interating with the camera, we only can manage one of these
    /// instances at a time.
    @MainActor private static var activeInstance: DualCameraManager?


    override public init() {
        super.init()
        
        frontCameraStream = AsyncStream { continuation in
            self.frontCameraContinuation = continuation
        }

        backCameraStream = AsyncStream { continuation in
            self.backCameraContinuation = continuation
        }
    }
    
    @MainActor
    public func startSession() async throws {
        // Check if another instance is active (on the main actor)
        if let activeInstance = Self.activeInstance, activeInstance !== self {
            throw DualCameraError.multipleInstancesNotSupported
        }
        
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw DualCameraError.multiCamNotSupported
        }
        
        guard await requestCameraPermission() else {
            throw DualCameraError.permissionDenied
        }
        
        if self.session.isRunning { return }
        
        self.session.beginConfiguration()
        do {
            try self.configureCameras()
        } catch {
            self.session.commitConfiguration()
            return
        }
        self.session.commitConfiguration()
        self.session.startRunning()
        
        // Mark this instance as active
        Self.activeInstance = self
    }

    public func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                
                // Switch to main actor to modify static property
                Task { @MainActor in
                    if Self.activeInstance === self {
                        Self.activeInstance = nil
                    }
                }
            }
        }
    }
    
    @MainActor
    public func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            return true
        } else if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return false
        }
    }

    private func configureCameras() throws {
        try configureCameraInputs()
        configureVideoOutputs()
    }

    /// Adds front and back cameras as session inputs
    private func configureCameraInputs() throws {
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw DualCameraError.cameraUnavailable(position: .front)
        }
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw DualCameraError.cameraUnavailable(position: .back)
        }
        
        let frontInput = try AVCaptureDeviceInput(device: frontCamera)
        let backInput = try AVCaptureDeviceInput(device: backCamera)
        
        if session.canAddInput(frontInput) {
            session.addInput(frontInput)
            frontCameraInput = frontInput
        }
        
        if session.canAddInput(backInput) {
            session.addInput(backInput)
            backCameraInput = backInput
        }
    }
}

extension DualCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        pixelBuffer

        let isFrontCamera = connection.inputPorts.contains { $0.sourceDevicePosition == .front }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        let wrappedPixelBuffer = PixelBufferWrapper(buffer: pixelBuffer)
        if isFrontCamera {
            self.frontCameraContinuation?.yield(wrappedPixelBuffer)
        } else {
            self.backCameraContinuation?.yield(wrappedPixelBuffer)
        }
    }
    
    private func configureVideoOutputs() {
        let frontOutput = AVCaptureVideoDataOutput()
        let backOutput = AVCaptureVideoDataOutput()

        frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        frontOutput.setSampleBufferDelegate(self, queue: DualCameraConstants.processingQueueFront)
        backOutput.setSampleBufferDelegate(self, queue: DualCameraConstants.processingQueueBack)

        if session.canAddOutput(frontOutput) {
            session.addOutput(frontOutput)
            frontCameraOutput = frontOutput
        }

        if session.canAddOutput(backOutput) {
            session.addOutput(backOutput)
            backCameraOutput = backOutput
        }

        for connection in session.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
}
