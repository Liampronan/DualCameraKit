// swiftlint:disable file_length
import AVFoundation
import UIKit

@MainActor
public protocol DualCameraCameraStreamSourcing {
    func startSession() async throws
    func stopSession()
    nonisolated func subscribe(to source: DualCameraSource) -> AsyncStream<PixelBufferWrapper>
    nonisolated func latestFrame(for source: DualCameraSource) -> PixelBufferWrapper?
    nonisolated func subscribeToFramePairs() -> AsyncStream<DualCameraFramePair>
    nonisolated func latestFramePair() -> DualCameraFramePair?
    nonisolated func diagnostics() -> DualCameraDiagnostics
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws
    func setZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws
    func setFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws
    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws
    func setWhiteBalanceMode(_ mode: AVCaptureDevice.WhiteBalanceMode, for source: DualCameraSource) throws
}

/// Manages low-level camera access and stream production
@MainActor
public final class DualCameraCameraStreamSource: NSObject, DualCameraCameraStreamSourcing {
    // Session management
    private let session = AVCaptureMultiCamSession()

    // Stream broadcasters
    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()
    private let framePairBroadcaster = FramePairBroadcaster()
    private let diagnosticsStore = DiagnosticsStore()
    private let outputRegistry = CaptureOutputRegistry()

    // Camera I/O
    private var frontCameraInput: AVCaptureDeviceInput?
    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraOutput: AVCaptureVideoDataOutput?
    private var backCameraOutput: AVCaptureVideoDataOutput?
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var interruptionObserver: NSObjectProtocol?
    private var isConfigured = false
    private let orientationProvider: DualCameraVideoOrientationProviding

    // Real AVCaptureMultiCamSession ownership is intentionally process-wide for now.
    // Tests that need multiple independent owners should use mock stream sources.
    @MainActor private static var activeInstance: DualCameraCameraStreamSource?

    /// Initialize camera hardware interface
    public init(orientationProvider: DualCameraVideoOrientationProviding = DeviceVideoOrientationProvider()) {
        self.orientationProvider = orientationProvider
        super.init()
    }

    /// Start camera session
    /// - Throws: DualCameraError if session cannot start
    @MainActor
    public func startSession() async throws {
        // Validate hardware ownership and support.
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
                diagnosticsStore.incrementConfigurationFailureCount()
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
        }

        if !session.isRunning {
            session.startRunning()
        }

        observeSessionNotificationsIfNeeded()
        orientationProvider.startObserving { [weak self] angle in
            self?.updateVideoRotationAngle(angle)
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

        orientationProvider.stopObserving()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
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

    nonisolated public func subscribeToFramePairs() -> AsyncStream<DualCameraFramePair> {
        framePairBroadcaster.subscribe()
    }

    nonisolated public func latestFramePair() -> DualCameraFramePair? {
        framePairBroadcaster.latestValue
    }

    nonisolated public func diagnostics() -> DualCameraDiagnostics {
        diagnosticsStore.snapshot
    }

    /// Sets the back-camera torch mode.
    @MainActor
    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        guard let device = backCameraInput?.device else {
            throw DualCameraError.cameraUnavailable(position: .back)
        }

        guard device.hasTorch else {
            // Some simulator or external-camera configurations have no torch.
            return
        }

        guard device.isTorchModeSupported(mode) else {
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if mode == .on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = mode
            }
        } catch {
            throw DualCameraError.configurationFailed
        }
    }

    public func setZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws {
        let device = try cameraDevice(for: source)
        try configureDevice(device) {
            let clampedFactor = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clampedFactor
        }
    }

    public func setFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws {
        let device = try cameraDevice(for: source)
        guard device.isFocusModeSupported(mode) else { return }
        try configureDevice(device) {
            device.focusMode = mode
        }
    }

    public func setExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws {
        let device = try cameraDevice(for: source)
        guard device.isExposureModeSupported(mode) else { return }
        try configureDevice(device) {
            device.exposureMode = mode
        }
    }

    public func setWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws {
        let device = try cameraDevice(for: source)
        guard device.isWhiteBalanceModeSupported(mode) else { return }
        try configureDevice(device) {
            device.whiteBalanceMode = mode
        }
    }

    // MARK: - Private Methods

    @MainActor
    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        if status == .authorized {
            return true
        } else if status == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .video)
        }
        return false
    }

    private func configureCameras() throws {
        try configureCameraInputs()
        try configureVideoOutputs()
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

    private func configureVideoOutputs() throws {
        let frontOutput = AVCaptureVideoDataOutput()
        let backOutput = AVCaptureVideoDataOutput()

        // Set pixel format
        frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        frontOutput.alwaysDiscardsLateVideoFrames = true
        backOutput.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(frontOutput), session.canAddOutput(backOutput) else {
            throw DualCameraError.configurationFailed
        }

        session.addOutput(frontOutput)
        session.addOutput(backOutput)
        frontCameraOutput = frontOutput
        backCameraOutput = backOutput
        outputRegistry.setOutput(frontOutput, for: .front)
        outputRegistry.setOutput(backOutput, for: .back)

        let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [frontOutput, backOutput])
        let synchronizedQueue = DispatchQueue(
            label: "DualCameraSynchronizedQueue",
            qos: .userInteractive
        )
        synchronizer.setDelegate(self, queue: synchronizedQueue)
        outputSynchronizer = synchronizer
        updateVideoRotationAngle(orientationProvider.currentVideoRotationAngle)
    }

    private func cameraDevice(for source: DualCameraSource) throws -> AVCaptureDevice {
        switch source {
        case .front:
            guard let device = frontCameraInput?.device else {
                throw DualCameraError.cameraUnavailable(position: .front)
            }
            return device
        case .back:
            guard let device = backCameraInput?.device else {
                throw DualCameraError.cameraUnavailable(position: .back)
            }
            return device
        }
    }

    private func configureDevice(_ device: AVCaptureDevice, changes: () throws -> Void) throws {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try changes()
        } catch {
            throw DualCameraError.configurationFailed
        }
    }

    private func updateVideoRotationAngle(_ angle: CGFloat) {
        for output in [frontCameraOutput, backCameraOutput] {
            guard let connection = output?.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else {
                continue
            }
            connection.videoRotationAngle = angle
        }
    }

    private func observeSessionNotificationsIfNeeded() {
        guard interruptionObserver == nil else { return }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [diagnosticsStore] _ in
            diagnosticsStore.incrementSessionInterruptionCount()
        }
    }
}

// MARK: - AVCapture Delegate Implementation
extension DualCameraCameraStreamSource: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated public func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let frontOutput = outputRegistry.output(for: .front),
              let backOutput = outputRegistry.output(for: .back),
              let frontData = synchronizedDataCollection.synchronizedData(
                for: frontOutput
              ) as? AVCaptureSynchronizedSampleBufferData,
              let backData = synchronizedDataCollection.synchronizedData(
                for: backOutput
              ) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }

        guard !frontData.sampleBufferWasDropped, !backData.sampleBufferWasDropped else {
            diagnosticsStore.incrementDroppedFramePairCount()
            return
        }

        let frontSampleBuffer = frontData.sampleBuffer
        let backSampleBuffer = backData.sampleBuffer

        guard let frontPixelBuffer = CMSampleBufferGetImageBuffer(frontSampleBuffer),
              let backPixelBuffer = CMSampleBufferGetImageBuffer(backSampleBuffer) else {
            return
        }

        let frontFrame = PixelBufferWrapper(buffer: frontPixelBuffer, sampleBuffer: frontSampleBuffer)
        let backFrame = PixelBufferWrapper(buffer: backPixelBuffer, sampleBuffer: backSampleBuffer)
        let timestamp = min(
            CMSampleBufferGetPresentationTimeStamp(frontSampleBuffer),
            CMSampleBufferGetPresentationTimeStamp(backSampleBuffer)
        )
        let framePair = DualCameraFramePair(front: frontFrame, back: backFrame, timestamp: timestamp)

        frontBroadcaster.send(frontFrame)
        backBroadcaster.send(backFrame)
        framePairBroadcaster.send(framePair)
    }
}

public final class DualCameraMockCameraStreamSource: DualCameraCameraStreamSourcing {
    public private(set) var torchMode: AVCaptureDevice.TorchMode = .off
    public private(set) var zoomFactors: [DualCameraSource: CGFloat] = [:]
    public private(set) var focusModes: [DualCameraSource: AVCaptureDevice.FocusMode] = [:]
    public private(set) var exposureModes: [DualCameraSource: AVCaptureDevice.ExposureMode] = [:]
    public private(set) var whiteBalanceModes: [DualCameraSource: AVCaptureDevice.WhiteBalanceMode] = [:]

    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()
    private let framePairBroadcaster = FramePairBroadcaster()
    private let diagnosticsStore = DiagnosticsStore()
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

    nonisolated public func subscribeToFramePairs() -> AsyncStream<DualCameraFramePair> {
        framePairBroadcaster.subscribe()
    }

    nonisolated public func latestFramePair() -> DualCameraFramePair? {
        framePairBroadcaster.latestValue
    }

    nonisolated public func diagnostics() -> DualCameraDiagnostics {
        diagnosticsStore.snapshot
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        torchMode = mode
    }

    public func setZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws {
        zoomFactors[source] = factor
    }

    public func setFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws {
        focusModes[source] = mode
    }

    public func setExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws {
        exposureModes[source] = mode
    }

    public func setWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws {
        whiteBalanceModes[source] = mode
    }

    private func sendMockFrames(sequence: Int) {
        let mockSize = CGSize(width: 360, height: 640)
        var frontFrame: PixelBufferWrapper?
        var backFrame: PixelBufferWrapper?

        if let frontBuffer = mockPixelBuffer(
            size: mockSize,
            hue: CGFloat((sequence * 9) % 360) / 360,
            saturation: 1,
            brightness: 1
        ) {
            let wrapper = PixelBufferWrapper(buffer: frontBuffer)
            frontFrame = wrapper
            frontBroadcaster.send(wrapper)
        }

        if let backBuffer = mockPixelBuffer(
            size: mockSize,
            hue: CGFloat((280 + sequence * 7) % 360) / 360,
            saturation: 1,
            brightness: 0.58
        ) {
            let wrapper = PixelBufferWrapper(buffer: backBuffer)
            backFrame = wrapper
            backBroadcaster.send(wrapper)
        }

        if let frontFrame, let backFrame {
            framePairBroadcaster.send(DualCameraFramePair(front: frontFrame, back: backFrame))
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

private final class CaptureOutputRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [DualCameraSource: AVCaptureVideoDataOutput] = [:]

    func setOutput(_ output: AVCaptureVideoDataOutput, for source: DualCameraSource) {
        lock.lock()
        outputs[source] = output
        lock.unlock()
    }

    func output(for source: DualCameraSource) -> AVCaptureVideoDataOutput? {
        lock.lock()
        defer { lock.unlock() }
        return outputs[source]
    }
}

private final class DiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var droppedFramePairCount = 0
    private var sessionInterruptionCount = 0
    private var configurationFailureCount = 0

    var snapshot: DualCameraDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return DualCameraDiagnostics(
            droppedFramePairCount: droppedFramePairCount,
            sessionInterruptionCount: sessionInterruptionCount,
            configurationFailureCount: configurationFailureCount
        )
    }

    func incrementDroppedFramePairCount() {
        lock.lock()
        droppedFramePairCount += 1
        lock.unlock()
    }

    func incrementSessionInterruptionCount() {
        lock.lock()
        sessionInterruptionCount += 1
        lock.unlock()
    }

    func incrementConfigurationFailureCount() {
        lock.lock()
        configurationFailureCount += 1
        lock.unlock()
    }
}
