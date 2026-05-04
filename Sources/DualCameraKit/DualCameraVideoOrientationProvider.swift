import UIKit

@MainActor
public protocol DualCameraVideoOrientationProviding: AnyObject {
    var currentVideoRotationAngle: CGFloat { get }
    func startObserving(_ onChange: @escaping @MainActor @Sendable (CGFloat) -> Void)
    func stopObserving()
}

@MainActor
public final class DeviceVideoOrientationProvider: DualCameraVideoOrientationProviding {
    private var observer: NSObjectProtocol?
    private var onChange: (@MainActor @Sendable (CGFloat) -> Void)?

    public init() {}

    public var currentVideoRotationAngle: CGFloat {
        Self.videoRotationAngle(for: UIDevice.current.orientation)
    }

    public func startObserving(_ onChange: @escaping @MainActor @Sendable (CGFloat) -> Void) {
        self.onChange = onChange
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.onChange?(self.currentVideoRotationAngle)
                }
            }
        }

        onChange(currentVideoRotationAngle)
    }

    public func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        onChange = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    static func videoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        case .faceUp, .faceDown, .unknown:
            return 90
        @unknown default:
            return 90
        }
    }
}
