/// Defines different layouts for dual-camera display
public enum DualCameraLayout: Hashable, Sendable {

    case sideBySide
    case stackedVertical
    case piP(miniCamera: DualCameraSource, miniCameraPosition: MiniCameraPosition)

    /// Positions for mini camera
    public enum MiniCameraPosition: CaseIterable, Hashable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }
}
