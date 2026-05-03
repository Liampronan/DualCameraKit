import SwiftUI

struct CapturePreviewOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.94)
                .ignoresSafeArea()

            GeometryReader { proxy in
                VStack(spacing: 18) {
                    header

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: proxy.size.width - 32,
                            maxHeight: previewMaxHeight(for: proxy)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, topPadding(for: proxy))
                .padding(.bottom, bottomPadding(for: proxy))
            }
        }
    }

    private var header: some View {
        HStack {
            actionButton(systemName: "xmark", foregroundStyle: .black, backgroundStyle: .white, action: onDismiss)

            Spacer()

            Text("Review")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            actionButton(systemName: "checkmark", foregroundStyle: .black, backgroundStyle: .green, action: onConfirm)
        }
    }

    private func actionButton(
        systemName: String,
        foregroundStyle: Color,
        backgroundStyle: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 56, height: 56)
                .background(backgroundStyle, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func previewMaxHeight(for proxy: GeometryProxy) -> CGFloat {
        max(
            240,
            proxy.size.height - topPadding(for: proxy) - bottomPadding(for: proxy) - 88
        )
    }

    private func topPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.top + 16, 64)
    }

    private func bottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.bottom + 20, 28)
    }
}
