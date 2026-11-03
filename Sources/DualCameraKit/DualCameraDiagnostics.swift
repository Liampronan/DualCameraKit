import AVFoundation
import Foundation

/// Coarse-grained taxonomy for runtime capture events.
public enum DualCameraDiagnosticEventKind: Equatable, Sendable {
    case framePairDropped
    case sessionInterrupted
    case configurationFailed
    case controlUnsupported
    case controlAdjusted
    case controlFailed
}

/// Additional context for a runtime diagnostic event.
public enum DualCameraDiagnosticEventContext: Equatable, Sendable {
    case none
    case source(DualCameraSource)
    case sessionInterruption(reason: AVCaptureSession.InterruptionReason?)
    case configurationFailure(source: DualCameraSource?, errorDescription: String?)
    case control(
        source: DualCameraSource,
        control: DualCameraCameraControl,
        requestedValueDescription: String,
        appliedValueDescription: String?
    )
}

/// A timestamped diagnostic event emitted by the camera pipeline.
public struct DualCameraDiagnosticEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let kind: DualCameraDiagnosticEventKind
    public let context: DualCameraDiagnosticEventContext

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: DualCameraDiagnosticEventKind,
        context: DualCameraDiagnosticEventContext = .none
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.context = context
    }
}

public typealias DualCameraDiagnosticEventHandler = @MainActor (DualCameraDiagnosticEvent) -> Void

/// Lightweight runtime diagnostics for capture-session health.
public struct DualCameraDiagnostics: Equatable, Sendable {
    public let droppedFramePairCount: Int
    public let sessionInterruptionCount: Int
    public let configurationFailureCount: Int
    public let controlUnsupportedCount: Int
    public let controlAdjustmentCount: Int
    public let controlFailureCount: Int
    public let latestEvent: DualCameraDiagnosticEvent?

    public init(
        droppedFramePairCount: Int = 0,
        sessionInterruptionCount: Int = 0,
        configurationFailureCount: Int = 0,
        controlUnsupportedCount: Int = 0,
        controlAdjustmentCount: Int = 0,
        controlFailureCount: Int = 0,
        latestEvent: DualCameraDiagnosticEvent? = nil
    ) {
        self.droppedFramePairCount = droppedFramePairCount
        self.sessionInterruptionCount = sessionInterruptionCount
        self.configurationFailureCount = configurationFailureCount
        self.controlUnsupportedCount = controlUnsupportedCount
        self.controlAdjustmentCount = controlAdjustmentCount
        self.controlFailureCount = controlFailureCount
        self.latestEvent = latestEvent
    }
}

final class DiagnosticEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<DualCameraDiagnosticEvent>.Continuation] = [:]
    private var latestEvent: DualCameraDiagnosticEvent?

    func send(_ event: DualCameraDiagnosticEvent) {
        lock.lock()
        latestEvent = event
        let activeContinuations = continuations
        lock.unlock()

        for continuation in activeContinuations.values {
            continuation.yield(event)
        }
    }

    var latestValue: DualCameraDiagnosticEvent? {
        lock.lock()
        defer { lock.unlock() }
        return latestEvent
    }

    func subscribe() -> AsyncStream<DualCameraDiagnosticEvent> {
        let id = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(20)) { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }
}
