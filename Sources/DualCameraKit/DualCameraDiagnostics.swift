/// Lightweight runtime diagnostics for capture-session health.
public struct DualCameraDiagnostics: Equatable, Sendable {
    public let droppedFramePairCount: Int
    public let sessionInterruptionCount: Int
    public let configurationFailureCount: Int

    public init(
        droppedFramePairCount: Int = 0,
        sessionInterruptionCount: Int = 0,
        configurationFailureCount: Int = 0
    ) {
        self.droppedFramePairCount = droppedFramePairCount
        self.sessionInterruptionCount = sessionInterruptionCount
        self.configurationFailureCount = configurationFailureCount
    }
}
