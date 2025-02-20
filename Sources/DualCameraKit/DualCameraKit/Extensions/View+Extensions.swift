import SwiftUI 

extension View {
    /// Positions the mini camera based on its layout position
    func positioned(in position: CameraLayout.MiniCameraPosition, size: CGSize, padding: CGFloat) -> some View {
        GeometryReader { geometry in
            self
                .position(
                    getPosition(for: position, in: geometry.size, size: size, padding: padding)
                )
        }
    }
    /// Computes the appropriate position for mini-camera placement.
    private func getPosition(for position: CameraLayout.MiniCameraPosition, in screenSize: CGSize, size: CGSize, padding: CGFloat) -> CGPoint {
            switch position {
            case .topLeading:
                return CGPoint(x: size.width / 2 + padding, y: size.height / 2 + padding)
            case .topTrailing:
                return CGPoint(x: screenSize.width - size.width / 2 - padding, y: size.height / 2 + padding)
            case .bottomLeading:
                return CGPoint(x: size.width / 2 + padding, y: screenSize.height - size.height / 2 - padding)
            case .bottomTrailing:
                return CGPoint(x: screenSize.width - size.width / 2 - padding, y: screenSize.height - size.height / 2 - padding)
            }
        }
}
