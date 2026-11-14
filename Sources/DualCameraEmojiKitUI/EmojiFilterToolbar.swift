import DualCameraEmojiKit
import DualCameraKit
import DualCameraKitUI
import SwiftUI

/// Floating SwiftUI control bar for toggling and selecting emojis with `EmojiFaceFilterPlugin`.
public struct EmojiFilterToolbar: View {
    @Bindable private var plugin: EmojiFaceFilterPlugin
    private let emojis: [String]
    private let onConfigurationChanged: (@MainActor () -> Void)?

    /// Creates an emoji filter toolbar bound to `plugin`.
    public init(
        plugin: EmojiFaceFilterPlugin,
        emojis: [String] = EmojiAssignmentStrategy.defaultPalette,
        onConfigurationChanged: (@MainActor () -> Void)? = nil
    ) {
        self.plugin = plugin
        self.emojis = emojis.isEmpty ? EmojiAssignmentStrategy.defaultPalette : emojis
        self.onConfigurationChanged = onConfigurationChanged
    }

    public var body: some View {
        HStack(spacing: 10) {
            toggleButton

            if plugin.isEnabled {
                Divider()
                    .frame(height: 22)
                    .overlay(Color.white.opacity(0.25))

                ViewThatFits(in: .horizontal) {
                    enabledControlsRow
                    ScrollView(.horizontal, showsIndicators: false) {
                        enabledControlsRow
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var enabledControlsRow: some View {
        HStack(spacing: 6) {
            ForEach(emojis.prefix(6), id: \.self) { emoji in
                emojiButton(for: emoji)
            }
            paletteModeButton
        }
    }

    private var toggleButton: some View {
        Button {
            plugin.toggle()
            onConfigurationChanged?()
        } label: {
            Image(systemName: plugin.isEnabled ? "face.smiling.inverse" : "face.dashed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(plugin.isEnabled ? .yellow : .white)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(plugin.isEnabled ? "Disable Emoji Filter" : "Enable Emoji Filter")
    }

    private func emojiButton(for emoji: String) -> some View {
        let isSelected = plugin.configuration.assignment == .single(emoji)
        return Button {
            plugin.selectEmoji(emoji)
            onConfigurationChanged?()
        } label: {
            Text(emoji)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.28) : Color.clear)
                )
        }
        .accessibilityLabel("Emoji \(emoji)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var paletteModeButton: some View {
        let isPaletteSelected: Bool = {
            if case .palette = plugin.configuration.assignment {
                return true
            }
            return false
        }()

        return Button {
            plugin.selectPalette(emojis)
            onConfigurationChanged?()
        } label: {
            Image(systemName: "person.2.crop.square.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isPaletteSelected ? Color.white.opacity(0.28) : Color.clear)
                )
        }
        .accessibilityLabel("Multi-Face Palette Mode")
        .accessibilityAddTraits(isPaletteSelected ? .isSelected : [])
    }
}

#Preview("Emoji Filter Toolbar") {
    ZStack {
        Color.black.ignoresSafeArea()
        EmojiFilterToolbar(plugin: EmojiFaceFilterPlugin())
    }
}
