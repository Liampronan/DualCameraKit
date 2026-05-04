/// Describes how camera imagery is fitted into a preview or capture region.
public enum DualCameraContentMode: Sendable {
    /// Fill the target region while preserving aspect ratio. Content may be cropped.
    case aspectFill

    /// Fit the whole image inside the target region while preserving aspect ratio.
    case aspectFit
}
