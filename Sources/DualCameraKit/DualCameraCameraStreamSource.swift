import AVFoundation
import UIKit

@MainActor
public protocol DualCameraCameraStreamSourcing {
    func startSession() async throws
    func stopSession()
    nonisolated func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper>
    nonisolated func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper?
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws
}

/// Manages low-level camera access and stream production
@MainActor
public final class DualCameraCameraStreamSource: NSObject, DualCameraCameraStreamSourcing {
    // Session management
    private let session = AVCaptureMultiCamSession()

    // Stream broadcasters
    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()

    // Camera I/O
    private var frontCameraInput: AVCaptureDeviceInput?
    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraOutput: AVCaptureVideoDataOutput?
    private var backCameraOutput: AVCaptureVideoDataOutput?
    private var isConfigured = false

    // Instance management
    @MainActor private static var activeInstance: DualCameraCameraStreamSource?

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

        // Configure once, then start/stop the same capture graph on later appearances.
        if !isConfigured {
            session.beginConfiguration()
            do {
                try configureCameras()
                isConfigured = true
            } catch {
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
        }

        if !session.isRunning {
            session.startRunning()
        }

        Self.activeInstance = self
    }

    /// Stops the camera capture session
    @MainActor
    public func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }

        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
    }

    /// Creates an explicit subscription to a camera stream.
    nonisolated public func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        switch source {
        case .front:
            return frontBroadcaster.subscribe()
        case .back:
            return backBroadcaster.subscribe()
        }
    }

    /// Returns the newest frame delivered for a camera source.
    nonisolated public func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper? {
        switch source {
        case .front:
            return frontBroadcaster.latestValue
        case .back:
            return backBroadcaster.latestValue
        }
    }

    /// Sets the back-camera torch mode.
    @MainActor
    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        guard let device = backCameraInput?.device else {
            throw DualCameraError.cameraUnavailable(position: .back)
        }

        guard device.hasTorch else {
            // Front camera usually doesn't have torch, silently ignore
            return
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            throw DualCameraError.configurationFailed
        }
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
extension DualCameraCameraStreamSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Receives camera frames from AVFoundation on background threads
    /// This method is called by the system on capture queue threads
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Set portrait orientation for the captured camera frames.
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Broadcast to appropriate stream
        let wrappedBuffer = PixelBufferWrapper(buffer: pixelBuffer)
        let isFrontCamera = connection.inputPorts.contains { $0.sourceDevicePosition == .front }

        if isFrontCamera {
            frontBroadcaster.send(wrappedBuffer)
        } else {
            backBroadcaster.send(wrappedBuffer)
        }
    }
}

public final class DualCameraMockCameraStreamSource: DualCameraCameraStreamSourcing {
    public private(set) var torchMode: AVCaptureDevice.TorchMode = .off

    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()
    private let animated: Bool
    private var frameTask: Task<Void, Never>?

    public init(animated: Bool = false) {
        self.animated = animated
    }

    public func startSession() async throws {
        sendMockFrames(sequence: 0)

        guard animated, frameTask == nil else { return }

        frameTask = Task { [weak self] in
            var sequence = 1

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self?.sendMockFrames(sequence: sequence)
                }
                sequence += 1
            }
        }
    }

    public func stopSession() {
        frameTask?.cancel()
        frameTask = nil
    }

    nonisolated public func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper> {
        switch source {
        case .front:
            return frontBroadcaster.subscribe()
        case .back:
            return backBroadcaster.subscribe()
        }
    }

    nonisolated public func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper? {
        switch source {
        case .front:
            return frontBroadcaster.latestValue
        case .back:
            return backBroadcaster.latestValue
        }
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        torchMode = mode
    }

    private func sendMockFrames(sequence: Int) {
        let mockSize = CGSize(width: 360, height: 640)

        if let frontBuffer = mockPixelBuffer(
            size: mockSize,
            hue: CGFloat((sequence * 9) % 360) / 360,
            saturation: 1,
            brightness: 1
        ) {
            frontBroadcaster.send(PixelBufferWrapper(buffer: frontBuffer))
        }

        if let backBuffer = mockPixelBuffer(
            size: mockSize,
            hue: CGFloat((280 + sequence * 7) % 360) / 360,
            saturation: 1,
            brightness: 0.58
        ) {
            backBroadcaster.send(PixelBufferWrapper(buffer: backBuffer))
        }
    }

    private func mockPixelBuffer(
        size: CGSize,
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> CVPixelBuffer? {
        UIColor(
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: 1
        )
        .asImage(size)
        .pixelBuffer()
    }
}
