import Foundation


public enum DualCameraVideoRecordingMode: CaseIterable, Identifiable, Sendable, Equatable {
    /// For now, DualCameraKit is setup to handle these two recorders with these configs.
    /// Specifically, we are not yet formally support the .cpuBased(.init(mode: .fullScreen)) config though it may work (code is not tested yet).
    public static var allCases: [DualCameraVideoRecordingMode] {
        [
            .cpuBased(.init(photoCaptureMode: .fullScreen)),
            .replayKit(nil)
        ]
    }
    
    case cpuBased(DualCameraCPUVideoRecorderConfig)
    case replayKit(DualCameraReplayKitVideoRecorderConfig? = nil)
    public var id: String { displayName }
    
    public var displayName: String {
        switch self {
        case .cpuBased: "CPU Recorder - Full Screen Capture"
        case .replayKit: "ReplayKit - Full ScreenCapture"
        }
    }
}

