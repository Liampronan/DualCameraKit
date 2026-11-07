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
    nonisolated func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent>
    nonisolated func diagnosticsSnapshot() -> DualCameraDiagnostics
    nonisolated func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent)
    func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities
    @discardableResult
    func applyTorchMode(_ mode: AVCaptureDevice.TorchMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult
    @discardableResult
    func applyFocusMode(_ mode: AVCaptureDevice.FocusMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyExposureMode(_ mode: AVCaptureDevice.ExposureMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
    @discardableResult
    func applyWhiteBalanceMode(_ mode: AVCaptureDevice.WhiteBalanceMode, for source: DualCameraSource) throws
        -> DualCameraCameraControlResult
}

/// Manages low-level camera access and stream production
@MainActor
public final class DualCameraCameraStreamSource: NSObject, DualCameraCameraStreamSourcing {
    // Session management
    private let session: AVCaptureMultiCamSession
    private let sessionRunner: SessionLifecycleRunner
    private let isMultiCamSupported: () -> Bool
    private let permissionRequester: @MainActor () async -> Bool
    private let cameraConfigurer: (@MainActor () throws -> Void)?

    // Stream broadcasters
    private let frontBroadcaster = PixelBufferBroadcaster()
    private let backBroadcaster = PixelBufferBroadcaster()
    private let framePairBroadcaster = FramePairBroadcaster()
    private let diagnosticEventBroadcaster = DiagnosticEventBroadcaster()
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
    /// Whether the front camera video connection is horizontally mirrored.
    public let mirrorsFrontCamera: Bool

    // Real AVCaptureMultiCamSession ownership is intentionally process-wide for now.
    // Tests that need multiple independent owners should use mock stream sources.
    @MainActor private static var activeInstance: DualCameraCameraStreamSource?

    /// Initialize camera hardware interface.
    public init(
        orientationProvider: DualCameraVideoOrientationProviding = DeviceVideoOrientationProvider(),
        mirrorsFrontCamera: Bool = true
    ) {
        let session = AVCaptureMultiCamSession()
        self.session = session
        self.sessionRunner = SessionLifecycleRunner(session: session)
        self.isMultiCamSupported = { AVCaptureMultiCamSession.isMultiCamSupported }
        self.permissionRequester = Self.requestCameraPermission
        self.cameraConfigurer = nil
        self.orientationProvider = orientationProvider
        self.mirrorsFrontCamera = mirrorsFrontCamera
        super.init()
    }

    /// Internal initializer for injecting session lifecycle and hardware hooks in tests.
    init(
        orientationProvider: DualCameraVideoOrientationProviding = DeviceVideoOrientationProvider(),
        mirrorsFrontCamera: Bool = true,
        sessionRunner: SessionLifecycleRunner,
        isMultiCamSupported: @escaping () -> Bool = { true },
        permissionRequester: @escaping @MainActor () async -> Bool = { true },
        cameraConfigurer: @escaping @MainActor () throws -> Void = {}
    ) {
        self.session = AVCaptureMultiCamSession()
        self.sessionRunner = sessionRunner
        self.isMultiCamSupported = isMultiCamSupported
        self.permissionRequester = permissionRequester
        self.cameraConfigurer = cameraConfigurer
        self.orientationProvider = orientationProvider
        self.mirrorsFrontCamera = mirrorsFrontCamera
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

        guard isMultiCamSupported() else {
            throw DualCameraError.multiCamNotSupported
        }

        let stopGeneration = sessionRunner.currentStopGeneration()

        // Check permissions
        guard await permissionRequester() else {
            throw DualCameraError.permissionDenied
        }

        try sessionRunner.ensureNotStopped(since: stopGeneration)

        // Configure once, then start/stop the same capture graph on later appearances.
        if !isConfigured {
            session.beginConfiguration()
            do {
                if let cameraConfigurer {
                    try cameraConfigurer()
                } else {
                    try configureCameras()
                }
                isConfigured = true
            } catch {
                recordDiagnosticEvent(
                    DualCameraDiagnosticEvent(
                        kind: .configurationFailed,
                        context: .configurationFailure(source: nil, errorDescription: error.localizedDescription)
                    )
                )
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
        }

        try await sessionRunner.startRunningIfNeeded(since: stopGeneration)

        if let activeInstance = Self.activeInstance, activeInstance !== self {
            sessionRunner.stopRunningIfNeeded()
            throw DualCameraError.multipleInstancesNotSupported
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
        sessionRunner.stopRunningIfNeeded()

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

    nonisolated public func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        diagnosticEventBroadcaster.subscribe()
    }

    nonisolated public func diagnosticsSnapshot() -> DualCameraDiagnostics {
        diagnosticsStore.snapshot
    }

    // MARK: - Private Methods

    /// Requests video capture permission if not already determined.
    @MainActor
    private static func requestCameraPermission() async -> Bool {
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

        // No preset or activeFormat is chosen here, so frame sizes are each device's default format, which
        // varies by model. Log them so simulator fixtures (DualCameraTestPattern) can be matched to devices.
        for (name, device) in [("front", frontCamera), ("back", backCamera)] {
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            // Dimensions are in sensor (landscape) orientation; delivered frames are rotated to portrait.
            DualCameraLogger.camera.info(
                "\(name, privacy: .public) camera active format: \(dimensions.width)x\(dimensions.height)"
            )
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

    nonisolated public func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent) {
        diagnosticsStore.record(event)
        diagnosticEventBroadcaster.send(event)
    }

    /// Applies the current video rotation angle and front-camera mirroring setting to active connections.
    private func updateVideoRotationAngle(_ angle: CGFloat) {
        for output in [frontCameraOutput, backCameraOutput] {
            guard let connection = output?.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else {
                continue
            }
            connection.videoRotationAngle = angle
        }

        if let frontConnection = frontCameraOutput?.connection(with: .video),
           frontConnection.isVideoMirroringSupported {
            frontConnection.automaticallyAdjustsVideoMirroring = false
            frontConnection.isVideoMirrored = mirrorsFrontCamera
        }
    }

    private func observeSessionNotificationsIfNeeded() {
        guard interruptionObserver == nil else { return }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            let reason = rawReason.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            self?.recordDiagnosticEvent(
                DualCameraDiagnosticEvent(
                    kind: .sessionInterrupted,
                    context: .sessionInterruption(reason: reason)
                )
            )
        }
    }
}

// MARK: - Camera Controls
extension DualCameraCameraStreamSource {
    public func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities {
        let device = try cameraDevice(for: source)
        return capabilities(for: device, source: source)
    }

    /// Applies a torch mode to a specific camera when that camera supports torch.
    @discardableResult
    @MainActor
    public func applyTorchMode(
        _ mode: AVCaptureDevice.TorchMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let device = try cameraDevice(for: source)
        guard device.hasTorch else {
            return recordUnsupportedControl(.torch, source: source, requestedValueDescription: "\(mode)")
        }

        guard device.isTorchModeSupported(mode) else {
            return recordUnsupportedControl(.torch, source: source, requestedValueDescription: "\(mode)")
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if mode == .on {
                guard device.isTorchAvailable else {
                    return recordUnsupportedControl(.torch, source: source, requestedValueDescription: "\(mode)")
                }
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = mode
            }
            return .applied
        } catch {
            recordControlFailure(.torch, source: source, requestedValueDescription: "\(mode)")
            throw DualCameraError.configurationFailed
        }
    }

    @discardableResult
    public func applyZoomFactor(
        _ factor: CGFloat,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let device = try cameraDevice(for: source)

        guard factor.isFinite else {
            recordControlFailure(.zoom, source: source, requestedValueDescription: "\(factor)")
            throw DualCameraError.configurationFailed
        }

        let minimumFactor = device.minAvailableVideoZoomFactor
        let maximumFactor = max(minimumFactor, device.maxAvailableVideoZoomFactor)
        let clampedFactor = min(max(factor, minimumFactor), maximumFactor)

        do {
            try configureDevice(device) {
                device.videoZoomFactor = clampedFactor
            }
        } catch {
            recordControlFailure(.zoom, source: source, requestedValueDescription: "\(factor)")
            throw error
        }

        if clampedFactor != factor {
            return recordAdjustedControl(
                .zoom,
                source: source,
                requestedValueDescription: "\(factor)",
                appliedValueDescription: "\(clampedFactor)"
            )
        }

        return .applied
    }

    @discardableResult
    public func applyFocusMode(
        _ mode: AVCaptureDevice.FocusMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let device = try cameraDevice(for: source)
        guard device.isFocusModeSupported(mode) else {
            return recordUnsupportedControl(.focus, source: source, requestedValueDescription: "\(mode)")
        }
        do {
            try configureDevice(device) {
                device.focusMode = mode
            }
            return .applied
        } catch {
            recordControlFailure(.focus, source: source, requestedValueDescription: "\(mode)")
            throw error
        }
    }

    @discardableResult
    public func applyExposureMode(
        _ mode: AVCaptureDevice.ExposureMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let device = try cameraDevice(for: source)
        guard device.isExposureModeSupported(mode) else {
            return recordUnsupportedControl(.exposure, source: source, requestedValueDescription: "\(mode)")
        }
        do {
            try configureDevice(device) {
                device.exposureMode = mode
            }
            return .applied
        } catch {
            recordControlFailure(.exposure, source: source, requestedValueDescription: "\(mode)")
            throw error
        }
    }

    @discardableResult
    public func applyWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let device = try cameraDevice(for: source)
        guard device.isWhiteBalanceModeSupported(mode) else {
            return recordUnsupportedControl(.whiteBalance, source: source, requestedValueDescription: "\(mode)")
        }
        do {
            try configureDevice(device) {
                device.whiteBalanceMode = mode
            }
            return .applied
        } catch {
            recordControlFailure(.whiteBalance, source: source, requestedValueDescription: "\(mode)")
            throw error
        }
    }

    // MARK: - Camera Control Helpers

    private func capabilities(
        for device: AVCaptureDevice,
        source: DualCameraSource
    ) -> DualCameraCameraCapabilities {
        DualCameraCameraCapabilities(
            source: source,
            supportsTorch: device.hasTorch,
            supportedTorchModes: supportedTorchModes(for: device),
            zoom: DualCameraZoomCapability(
                isSupported: device.maxAvailableVideoZoomFactor > device.minAvailableVideoZoomFactor,
                minimumFactor: device.minAvailableVideoZoomFactor,
                maximumFactor: max(device.minAvailableVideoZoomFactor, device.maxAvailableVideoZoomFactor),
                currentFactor: device.videoZoomFactor
            ),
            supportedFocusModes: supportedFocusModes(for: device),
            supportedExposureModes: supportedExposureModes(for: device),
            supportedWhiteBalanceModes: supportedWhiteBalanceModes(for: device)
        )
    }

    private func supportedTorchModes(for device: AVCaptureDevice) -> Set<AVCaptureDevice.TorchMode> {
        guard device.hasTorch else { return [] }
        return Set([.off, .on, .auto].filter { device.isTorchModeSupported($0) })
    }

    private func supportedFocusModes(for device: AVCaptureDevice) -> Set<AVCaptureDevice.FocusMode> {
        Set([
            AVCaptureDevice.FocusMode.locked,
            .autoFocus,
            .continuousAutoFocus
        ].filter { device.isFocusModeSupported($0) })
    }

    private func supportedExposureModes(for device: AVCaptureDevice) -> Set<AVCaptureDevice.ExposureMode> {
        Set([
            AVCaptureDevice.ExposureMode.locked,
            .autoExpose,
            .continuousAutoExposure,
            .custom
        ].filter { device.isExposureModeSupported($0) })
    }

    private func supportedWhiteBalanceModes(
        for device: AVCaptureDevice
    ) -> Set<AVCaptureDevice.WhiteBalanceMode> {
        Set([
            AVCaptureDevice.WhiteBalanceMode.locked,
            .autoWhiteBalance,
            .continuousAutoWhiteBalance
        ].filter { device.isWhiteBalanceModeSupported($0) })
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

    @discardableResult
    private nonisolated func recordUnsupportedControl(
        _ control: DualCameraCameraControl,
        source: DualCameraSource,
        requestedValueDescription: String
    ) -> DualCameraCameraControlResult {
        recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: .controlUnsupported,
                context: .control(
                    source: source,
                    control: control,
                    requestedValueDescription: requestedValueDescription,
                    appliedValueDescription: nil
                )
            )
        )
        return .unsupported
    }

    @discardableResult
    private nonisolated func recordAdjustedControl(
        _ control: DualCameraCameraControl,
        source: DualCameraSource,
        requestedValueDescription: String,
        appliedValueDescription: String
    ) -> DualCameraCameraControlResult {
        recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: .controlAdjusted,
                context: .control(
                    source: source,
                    control: control,
                    requestedValueDescription: requestedValueDescription,
                    appliedValueDescription: appliedValueDescription
                )
            )
        )
        return .adjusted(
            requestedValueDescription: requestedValueDescription,
            appliedValueDescription: appliedValueDescription
        )
    }

    private nonisolated func recordControlFailure(
        _ control: DualCameraCameraControl,
        source: DualCameraSource,
        requestedValueDescription: String
    ) {
        recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: .controlFailed,
                context: .control(
                    source: source,
                    control: control,
                    requestedValueDescription: requestedValueDescription,
                    appliedValueDescription: nil
                )
            )
        )
    }
}

// MARK: - AVCapture Delegate Implementation
extension DualCameraCameraStreamSource: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated public func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let frontOutput = outputRegistry.output(for: .front),
              let backOutput = outputRegistry.output(for: .back) else {
            return
        }

        let frontFrame = frame(from: synchronizedDataCollection, output: frontOutput)
        let backFrame = frame(from: synchronizedDataCollection, output: backOutput)

        if let frontFrame {
            frontBroadcaster.send(frontFrame.frame)
        }
        if let backFrame {
            backBroadcaster.send(backFrame.frame)
        }

        guard let frontFrame, let backFrame else {
            recordDiagnosticEvent(
                DualCameraDiagnosticEvent(
                    kind: .framePairDropped,
                    context: .none
                )
            )
            return
        }

        let timestamp = min(frontFrame.timestamp, backFrame.timestamp)
        let framePair = DualCameraFramePair(
            front: frontFrame.frame,
            back: backFrame.frame,
            timestamp: timestamp
        )
        framePairBroadcaster.send(framePair)
    }

    private nonisolated func frame(
        from synchronizedDataCollection: AVCaptureSynchronizedDataCollection,
        output: AVCaptureVideoDataOutput
    ) -> (frame: PixelBufferWrapper, timestamp: CMTime)? {
        guard let data = synchronizedDataCollection.synchronizedData(
            for: output
        ) as? AVCaptureSynchronizedSampleBufferData else {
            return nil
        }

        guard !data.sampleBufferWasDropped else {
            return nil
        }

        let sampleBuffer = data.sampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        return (
            PixelBufferWrapper(buffer: pixelBuffer, sampleBuffer: sampleBuffer),
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
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
    private let diagnosticEventBroadcaster = DiagnosticEventBroadcaster()
    private let diagnosticsStore = DiagnosticsStore()
    private let animated: Bool
    private let frameProvider: FrameProvider
    private var frameTask: Task<Void, Never>?

    /// Produces the pixel buffer for one camera at one frame index (0 on start, then 1, 2, … when animated).
    private typealias FrameProvider = @MainActor (DualCameraSource, Int) -> CVPixelBuffer?

    /// Serves flat colour frames whose hue changes every 250 ms when `animated` is true.
    public init(animated: Bool = false) {
        self.animated = animated
        self.frameProvider = Self.solidColorFrame(for:sequence:)
    }

    private init(animated: Bool, pixelBufferProvider: @escaping FrameProvider) {
        self.animated = animated
        self.frameProvider = pixelBufferProvider
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

    nonisolated public func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        diagnosticEventBroadcaster.subscribe()
    }

    nonisolated public func diagnosticsSnapshot() -> DualCameraDiagnostics {
        diagnosticsStore.snapshot
    }

    public func cameraCapabilities(for source: DualCameraSource) throws -> DualCameraCameraCapabilities {
        DualCameraCameraCapabilities(
            source: source,
            supportsTorch: source == .back,
            supportedTorchModes: source == .back ? [.off, .on] : [],
            zoom: DualCameraZoomCapability(
                isSupported: true,
                minimumFactor: 1,
                maximumFactor: 8,
                currentFactor: zoomFactors[source] ?? 1
            ),
            supportedFocusModes: [.locked, .autoFocus, .continuousAutoFocus],
            supportedExposureModes: [.locked, .autoExpose, .continuousAutoExposure],
            supportedWhiteBalanceModes: [.locked, .autoWhiteBalance, .continuousAutoWhiteBalance]
        )
    }

    @discardableResult
    public func applyTorchMode(
        _ mode: AVCaptureDevice.TorchMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        guard source == .back, mode == .off || mode == .on else {
            return recordUnsupportedControl(.torch, source: source, requestedValueDescription: "\(mode)")
        }
        torchMode = mode
        return .applied
    }

    @discardableResult
    public func applyZoomFactor(
        _ factor: CGFloat,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        let clampedFactor = min(max(factor, 1), 8)
        zoomFactors[source] = clampedFactor
        if clampedFactor != factor {
            return recordAdjustedControl(
                .zoom,
                source: source,
                requestedValueDescription: "\(factor)",
                appliedValueDescription: "\(clampedFactor)"
            )
        }
        return .applied
    }

    @discardableResult
    public func applyFocusMode(
        _ mode: AVCaptureDevice.FocusMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        guard [.locked, .autoFocus, .continuousAutoFocus].contains(mode) else {
            return recordUnsupportedControl(.focus, source: source, requestedValueDescription: "\(mode)")
        }
        focusModes[source] = mode
        return .applied
    }

    @discardableResult
    public func applyExposureMode(
        _ mode: AVCaptureDevice.ExposureMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        guard [.locked, .autoExpose, .continuousAutoExposure].contains(mode) else {
            return recordUnsupportedControl(.exposure, source: source, requestedValueDescription: "\(mode)")
        }
        exposureModes[source] = mode
        return .applied
    }

    @discardableResult
    public func applyWhiteBalanceMode(
        _ mode: AVCaptureDevice.WhiteBalanceMode,
        for source: DualCameraSource
    ) throws -> DualCameraCameraControlResult {
        guard [.locked, .autoWhiteBalance, .continuousAutoWhiteBalance].contains(mode) else {
            return recordUnsupportedControl(.whiteBalance, source: source, requestedValueDescription: "\(mode)")
        }
        whiteBalanceModes[source] = mode
        return .applied
    }

    private func sendMockFrames(sequence: Int) {
        var frontFrame: PixelBufferWrapper?
        var backFrame: PixelBufferWrapper?

        if let frontBuffer = frameProvider(.front, sequence) {
            let wrapper = PixelBufferWrapper(buffer: frontBuffer)
            frontFrame = wrapper
            frontBroadcaster.send(wrapper)
        }

        if let backBuffer = frameProvider(.back, sequence) {
            let wrapper = PixelBufferWrapper(buffer: backBuffer)
            backFrame = wrapper
            backBroadcaster.send(wrapper)
        }

        if let frontFrame, let backFrame {
            framePairBroadcaster.send(DualCameraFramePair(front: frontFrame, back: backFrame))
        }
    }

    private static func solidColorFrame(for source: DualCameraSource, sequence: Int) -> CVPixelBuffer? {
        let mockSize = CGSize(width: 360, height: 640)
        switch source {
        case .front:
            return mockPixelBuffer(
                size: mockSize,
                hue: CGFloat((sequence * 9) % 360) / 360,
                saturation: 1,
                brightness: 1
            )
        case .back:
            return mockPixelBuffer(
                size: mockSize,
                hue: CGFloat((280 + sequence * 7) % 360) / 360,
                saturation: 1,
                brightness: 0.58
            )
        }
    }

    private static func mockPixelBuffer(
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

    @discardableResult
    private func recordUnsupportedControl(
        _ control: DualCameraCameraControl,
        source: DualCameraSource,
        requestedValueDescription: String
    ) -> DualCameraCameraControlResult {
        recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: .controlUnsupported,
                context: .control(
                    source: source,
                    control: control,
                    requestedValueDescription: requestedValueDescription,
                    appliedValueDescription: nil
                )
            )
        )
        return .unsupported
    }

    @discardableResult
    private func recordAdjustedControl(
        _ control: DualCameraCameraControl,
        source: DualCameraSource,
        requestedValueDescription: String,
        appliedValueDescription: String
    ) -> DualCameraCameraControlResult {
        recordDiagnosticEvent(
            DualCameraDiagnosticEvent(
                kind: .controlAdjusted,
                context: .control(
                    source: source,
                    control: control,
                    requestedValueDescription: requestedValueDescription,
                    appliedValueDescription: appliedValueDescription
                )
            )
        )
        return .adjusted(
            requestedValueDescription: requestedValueDescription,
            appliedValueDescription: appliedValueDescription
        )
    }

    nonisolated public func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent) {
        diagnosticsStore.record(event)
        diagnosticEventBroadcaster.send(event)
    }
}

// MARK: - Fixture frames

@MainActor
extension DualCameraMockCameraStreamSource {
    /// Serves the same still image for each camera on every frame, so captures are deterministic.
    ///
    /// Frames have each image's pixel size (`size × scale`), so pass images whose aspect ratio matches the
    /// device streams you want to stand in for. Images that are not `.up` are redrawn upright first.
    public convenience init(front: UIImage, back: UIImage) {
        let frontBuffer = front.uprightPixelBuffer()
        let backBuffer = back.uprightPixelBuffer()
        self.init(animated: false, pixelBufferProvider: { source, _ in
            source == .front ? frontBuffer : backBuffer
        })
    }

    /// Serves frames from `frameProvider`, which receives the camera and a frame index that starts at 0.
    ///
    /// With `animated` false the provider is called once per camera each time the session starts, which
    /// suits still fixtures. With `animated` true it is also called every 250 ms with increasing indexes.
    /// Returning nil skips that camera's frame.
    public convenience init(
        animated: Bool = false,
        frameProvider: @escaping @MainActor (_ source: DualCameraSource, _ frameIndex: Int) -> UIImage?
    ) {
        self.init(animated: animated, pixelBufferProvider: { source, frameIndex in
            frameProvider(source, frameIndex)?.uprightPixelBuffer()
        })
    }

    /// Serves `DualCameraTestPattern` still frames: a grid, labelled corner markers, a centre crosshair and
    /// a FRONT or BACK label. Useful for catching crop, offset and aspect-ratio bugs in the Simulator.
    ///
    /// - Parameters:
    ///   - frontFrameSize: Pixel size of front camera frames. Defaults to portrait 3:4.
    ///   - backFrameSize: Pixel size of back camera frames. Defaults to portrait 3:4.
    public static func testPattern(
        frontFrameSize: CGSize = DualCameraTestPattern.defaultFrameSize,
        backFrameSize: CGSize = DualCameraTestPattern.defaultFrameSize
    ) -> DualCameraMockCameraStreamSource {
        DualCameraMockCameraStreamSource(
            front: DualCameraTestPattern.image(for: .front, size: frontFrameSize),
            back: DualCameraTestPattern.image(for: .back, size: backFrameSize)
        )
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
    private var captureFallbackCount = 0
    private var captureFrameGapExceededCount = 0
    private var sessionInterruptionCount = 0
    private var configurationFailureCount = 0
    private var controlUnsupportedCount = 0
    private var controlAdjustmentCount = 0
    private var controlFailureCount = 0
    private var latestEvent: DualCameraDiagnosticEvent?

    var snapshot: DualCameraDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return DualCameraDiagnostics(
            droppedFramePairCount: droppedFramePairCount,
            captureFallbackCount: captureFallbackCount,
            captureFrameGapExceededCount: captureFrameGapExceededCount,
            sessionInterruptionCount: sessionInterruptionCount,
            configurationFailureCount: configurationFailureCount,
            controlUnsupportedCount: controlUnsupportedCount,
            controlAdjustmentCount: controlAdjustmentCount,
            controlFailureCount: controlFailureCount,
            latestEvent: latestEvent
        )
    }

    func record(_ event: DualCameraDiagnosticEvent) {
        lock.lock()
        latestEvent = event
        switch event.kind {
        case .framePairDropped:
            droppedFramePairCount += 1
        case .captureUsedFallbackFrames:
            captureFallbackCount += 1
        case .captureFrameGapExceeded:
            captureFallbackCount += 1
            captureFrameGapExceededCount += 1
        case .sessionInterrupted:
            sessionInterruptionCount += 1
        case .configurationFailed:
            configurationFailureCount += 1
        case .controlUnsupported:
            controlUnsupportedCount += 1
        case .controlAdjusted:
            controlAdjustmentCount += 1
        case .controlFailed:
            controlFailureCount += 1
        }
        lock.unlock()
    }
}

/// Runs blocking `AVCaptureMultiCamSession` start/stop transitions on a serial background queue
/// so hardware startup never blocks `@MainActor`.
final class SessionLifecycleRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var stopGeneration: UInt64 = 0
    private let isRunning: () -> Bool
    private let startRunning: () -> Void
    private let stopRunning: () -> Void
    private let queue = DispatchQueue(label: "DualCameraSessionQueue", qos: .userInitiated)

    /// Creates a runner backed by a live `AVCaptureMultiCamSession`.
    convenience init(session: AVCaptureMultiCamSession) {
        self.init(
            isRunning: { session.isRunning },
            startRunning: { session.startRunning() },
            stopRunning: { session.stopRunning() }
        )
    }

    /// Creates a runner with custom start/stop closures for testing or session management.
    init(
        isRunning: @escaping () -> Bool,
        startRunning: @escaping () -> Void,
        stopRunning: @escaping () -> Void
    ) {
        self.isRunning = isRunning
        self.startRunning = startRunning
        self.stopRunning = stopRunning
    }

    /// Returns the current stop generation token used to detect stops across async suspension points.
    func currentStopGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return stopGeneration
    }

    /// Throws `CancellationError` if a stop has occurred since `expectedGeneration` or if the task is cancelled.
    func ensureNotStopped(since expectedGeneration: UInt64) throws {
        guard isNotStopped(since: expectedGeneration) else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    /// Starts the capture session on the serial queue if not running, throwing `CancellationError` if invalidated.
    func startRunningIfNeeded(since expectedGeneration: UInt64? = nil) async throws {
        let generation = expectedGeneration ?? currentStopGeneration()
        try ensureNotStopped(since: generation)

        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard isNotStopped(since: generation) else {
                        continuation.resume()
                        return
                    }
                    if !isRunning() {
                        startRunning()
                    }
                    if !isNotStopped(since: generation), isRunning() {
                        stopRunning()
                    }
                    continuation.resume()
                }
            }
            try ensureNotStopped(since: generation)
        } onCancel: {
            cancelStart(generation: generation)
        }
    }

    /// Invalidates any in-flight start and stops the capture session on the serial queue if running.
    func stopRunningIfNeeded() {
        lock.lock()
        stopGeneration &+= 1
        lock.unlock()

        queue.async { [self] in
            if isRunning() {
                stopRunning()
            }
        }
    }

    /// Invalidates an in-flight start for `expectedGeneration` when its task is cancelled.
    private func cancelStart(generation expectedGeneration: UInt64) {
        lock.lock()
        guard stopGeneration == expectedGeneration else {
            lock.unlock()
            return
        }
        stopGeneration &+= 1
        lock.unlock()

        queue.async { [self] in
            if isRunning() {
                stopRunning()
            }
        }
    }

    /// Returns `true` when no stop has occurred since `expectedGeneration`.
    private func isNotStopped(since expectedGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopGeneration == expectedGeneration
    }
}
