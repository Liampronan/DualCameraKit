import AVFoundation
import CoreGraphics

public enum DualCameraCameraControl: Equatable, Sendable {
    case torch
    case zoom
    case focus
    case exposure
    case whiteBalance
}

public enum DualCameraCameraControlResult: Equatable, Sendable {
    case applied
    case adjusted(requestedValueDescription: String, appliedValueDescription: String)
    case unsupported

    public var wasApplied: Bool {
        switch self {
        case .applied, .adjusted:
            return true
        case .unsupported:
            return false
        }
    }
}

public struct DualCameraZoomCapability: Equatable, Sendable {
    public let isSupported: Bool
    public let minimumFactor: CGFloat
    public let maximumFactor: CGFloat
    public let currentFactor: CGFloat

    public init(
        isSupported: Bool,
        minimumFactor: CGFloat,
        maximumFactor: CGFloat,
        currentFactor: CGFloat
    ) {
        self.isSupported = isSupported
        self.minimumFactor = minimumFactor
        self.maximumFactor = maximumFactor
        self.currentFactor = currentFactor
    }

    public static let unsupported = Self(
        isSupported: false,
        minimumFactor: 1,
        maximumFactor: 1,
        currentFactor: 1
    )
}

public struct DualCameraCameraCapabilities: Equatable {
    public let source: DualCameraSource
    public let supportsTorch: Bool
    public let supportedTorchModes: Set<AVCaptureDevice.TorchMode>
    public let zoom: DualCameraZoomCapability
    public let supportedFocusModes: Set<AVCaptureDevice.FocusMode>
    public let supportedExposureModes: Set<AVCaptureDevice.ExposureMode>
    public let supportedWhiteBalanceModes: Set<AVCaptureDevice.WhiteBalanceMode>

    public init(
        source: DualCameraSource,
        supportsTorch: Bool,
        supportedTorchModes: Set<AVCaptureDevice.TorchMode>,
        zoom: DualCameraZoomCapability,
        supportedFocusModes: Set<AVCaptureDevice.FocusMode>,
        supportedExposureModes: Set<AVCaptureDevice.ExposureMode>,
        supportedWhiteBalanceModes: Set<AVCaptureDevice.WhiteBalanceMode>
    ) {
        self.source = source
        self.supportsTorch = supportsTorch
        self.supportedTorchModes = supportedTorchModes
        self.zoom = zoom
        self.supportedFocusModes = supportedFocusModes
        self.supportedExposureModes = supportedExposureModes
        self.supportedWhiteBalanceModes = supportedWhiteBalanceModes
    }

    public static func unavailable(for source: DualCameraSource) -> Self {
        Self(
            source: source,
            supportsTorch: false,
            supportedTorchModes: [],
            zoom: .unsupported,
            supportedFocusModes: [],
            supportedExposureModes: [],
            supportedWhiteBalanceModes: []
        )
    }
}
