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
    private let session = AVCaptureMultiCamSession()

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

    nonisolated public func diagnosticEvents() -> AsyncStream<DualCameraDiagnosticEvent> {
        diagnosticEventBroadcaster.subscribe()
    }

    nonisolated public func diagnosticsSnapshot() -> DualCameraDiagnostics {
        diagnosticsStore.snapshot
    }

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
    public func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult {
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

    private nonisolated func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent) {
        diagnosticsStore.record(event)
        diagnosticEventBroadcaster.send(event)
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
    public func applyZoomFactor(_ factor: CGFloat, for source: DualCameraSource) throws -> DualCameraCameraControlResult {
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

    private func recordDiagnosticEvent(_ event: DualCameraDiagnosticEvent) {
        diagnosticsStore.record(event)
        diagnosticEventBroadcaster.send(event)
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
    private var controlUnsupportedCount = 0
    private var controlAdjustmentCount = 0
    private var controlFailureCount = 0
    private var latestEvent: DualCameraDiagnosticEvent?

    var snapshot: DualCameraDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return DualCameraDiagnostics(
            droppedFramePairCount: droppedFramePairCount,
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
