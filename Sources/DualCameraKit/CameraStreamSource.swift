import AVFoundation


/// Manages low-level camera access and stream production
@MainActor
public final class CameraStreamSource: NSObject {
    // Session management
    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "DualCameraKit.session")
    
    // Stream broadcasters
    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()
    
    // Camera I/O
    private var frontCameraInput: AVCaptureDeviceInput?
    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraOutput: AVCaptureVideoDataOutput?
    private var backCameraOutput: AVCaptureVideoDataOutput?
    
    // Instance management
    @MainActor private static var activeInstance: CameraStreamSource?
    
    /// Initialize camera hardware interface
    public override init() {
        super.init()
    }
    
    /// Start camera session
    /// - Throws: DualCameraError if session cannot start
    @MainActor
    public func startSession() async throws {
        // Validate instance & hardware support
        if let activeInstance = Self.activeInstance, activeInstance !== self {
            throw DualCameraError.multipleInstancesNotSupported
        }
        
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw DualCameraError.multiCamNotSupported
        }
        
        // Check permissions
        guard await requestCameraPermission() else {
            throw DualCameraError.permissionDenied
        }
        
        // Configure & start session
        if !session.isRunning {
            session.beginConfiguration()
            do {
                try configureCameras()
            } catch {
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
            session.startRunning()
            
            Self.activeInstance = self
        }
    }
    
    /// Stops the camera capture session
    /// This method can be called from any thread (nonisolated) and will safely dispatch
    /// session management work to the main thread internally.
    nonisolated public func stopSession() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if session.isRunning {
                session.stopRunning()
            }
            
            if Self.activeInstance === self {
                Self.activeInstance = nil
            }
        }
    }
    
    /// Get front camera stream
    /// This property is thread-safe and can be accessed from any context
    /// - Returns: AsyncStream of front camera frames
    nonisolated public var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        frontBroadcaster.subscribe()
    }
        
    /// Get back camera stream
    /// This property is thread-safe and can be accessed from any context
    /// - Returns: AsyncStream of back camera frames
    nonisolated public var backCameraStream: AsyncStream<PixelBufferWrapper> {
        backBroadcaster.subscribe()
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        if status == .authorized {
            return true
        } else if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return false
    }
    
    private func configureCameras() throws {
        try configureCameraInputs()
        configureVideoOutputs()
    }
    
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
    
    private func configureVideoOutputs() {
        let frontOutput = AVCaptureVideoDataOutput()
        let backOutput = AVCaptureVideoDataOutput()

        // Set pixel format
        frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        // IMPORTANT: Set this class as the sampleBufferDelegate
        frontOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "FrontCameraQueue"))
        backOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "BackCameraQueue"))

        // Add outputs to the session
        if session.canAddOutput(frontOutput) {
            session.addOutput(frontOutput)
            frontCameraOutput = frontOutput
        }
        if session.canAddOutput(backOutput) {
            session.addOutput(backOutput)
            backCameraOutput = backOutput
        }
    }
}

// MARK: - AVCapture Delegate Implementation
extension CameraStreamSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Receives camera frames from AVFoundation on background threads
    /// This method is called by the system on capture queue threads
    nonisolated public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Set orientation
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        // Broadcast to appropriate stream
        let wrappedBuffer = PixelBufferWrapper(buffer: pixelBuffer)
        let isFrontCamera = connection.inputPorts.contains { $0.sourceDevicePosition == .front }
        
        
        if isFrontCamera {
            Updater.updateBroadcast(wrappedBuffer: wrappedBuffer, broadcaster: frontBroadcaster)
        } else {
            Updater.updateBroadcast(wrappedBuffer: wrappedBuffer, broadcaster: backBroadcaster)
        }
    }
    
    /// Helper to safely bridge between capture threads and the async runtime
    /// Uses @unchecked Sendable because it only contains static methods with
    /// no mutable state, making it thread-safe
    private struct Updater: @unchecked Sendable {
        static func updateBroadcast(wrappedBuffer: PixelBufferWrapper, broadcaster: PixelBufferBroadcaster) {
            Task {
                await broadcaster.broadcast(wrappedBuffer)
            }
        }
    }
    
}
