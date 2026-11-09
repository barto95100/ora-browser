import SwiftUI

/// The icon (a symbol or an emoji), color and theme of a space, edited in
/// place: the space editor and the first-launch assistant.
struct SpaceLookFields: View {
    @Binding var look: SpaceLook

    @Environment(\.theme) private var theme
    @State private var isEmojiMode = false
    @State private var isEmojiPickerOpen = false
    /// Once the person switches, the mode no longer follows the look.
    @State private var choseMode = false

    private let iconColumns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            iconSection
            colorSection
            themeSection
        }
        // The look can arrive after this view appears (the editor sets it up
        // in its own onAppear): the mode follows it until the person switches.
        .onChange(of: look, initial: true) {
            if !choseMode {
                isEmojiMode = look.iconSymbol == nil && look.emoji != ContainerConstants.defaultEmoji
            }
        }
    }

    // MARK: - Icon

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(String(localized: "Icon"))
                Spacer()
                Button(isEmojiMode ? "Symbols" : "Emoji") {
                    choseMode = true
                    isEmojiMode.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.mutedBackground, in: Capsule())
            }
            if isEmojiMode {
                emojiPicker
            } else {
                LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 6) {
                    iconChoice(nil)
                    ForEach(SpaceIcon.symbols, id: \.self) { iconChoice($0) }
                }
            }
        }
    }

    /// A symbol, or nil for none (the space shows its emoji).
    private func iconChoice(_ symbol: String?) -> some View {
        let isSelected = look.iconSymbol == symbol
        return Button {
            look.iconSymbol = symbol
        } label: {
            Image(systemName: symbol ?? "nosign")
                .font(.system(size: 15))
                .foregroundColor(isSelected ? look.color?.color ?? theme.foreground : theme.mutedForeground)
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? theme.mutedBackground : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol == nil ? String(localized: "No symbol (emoji)") : symbol ?? "")
    }

    private var emojiPicker: some View {
        HStack(spacing: 10) {
            Button {
                isEmojiPickerOpen.toggle()
            } label: {
                Text(look.emoji)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(theme.mutedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEmojiPickerOpen, arrowEdge: .bottom) {
                EmojiPickerView { selected in
                    look.emoji = selected
                    look.iconSymbol = nil
                    isEmojiPickerOpen = false
                }
            }
            Text("The emoji is used when no symbol is chosen.")
                .font(.system(size: 11))
                .foregroundColor(theme.mutedForeground)
        }
    }

    // MARK: - Color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(String(localized: "Color"))
                Spacer()
                Text(look.color?.title ?? String(localized: "color.none", defaultValue: "None"))
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
            }
            HStack(spacing: 12) {
                colorChoice(nil)
                ForEach(SpaceColor.allCases) { colorChoice($0) }
            }
        }
    }

    private func colorChoice(_ choice: SpaceColor?) -> some View {
        let isSelected = look.color == choice
        return Button {
            look.color = choice
        } label: {
            ZStack {
                if let choice {
                    Circle().fill(choice.color)
                } else {
                    Image(systemName: "nosign")
                        .font(.system(size: 17))
                        .foregroundColor(theme.mutedForeground)
                }
            }
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().stroke(isSelected ? choice?.color ?? theme.foreground : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice?.title ?? String(localized: "color.none", defaultValue: "None"))
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(String(localized: "Theme"))
                Spacer()
                Text(look.theme?.title ?? String(localized: "theme.none", defaultValue: "None"))
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
            }
            HStack(spacing: 6) {
                themeChoice(nil)
                ForEach(SpaceTheme.allCases) { themeChoice($0) }
            }
        }
    }

    /// A theme: its background, with its accent in a corner.
    private func themeChoice(_ choice: SpaceTheme?) -> some View {
        let isSelected = look.theme == choice
        return Button {
            look.theme = choice
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let choice {
                    Circle().fill(choice.background)
                    // A quarter of the circle, once clipped to it.
                    Rectangle()
                        .fill(choice.accent)
                        .frame(width: 11, height: 11)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Image(systemName: "nosign")
                        .font(.system(size: 17))
                        .foregroundColor(theme.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            .padding(2)
            .overlay(Circle().stroke(isSelected ? theme.foreground.opacity(0.7) : .clear, lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice?.title ?? String(localized: "theme.none", defaultValue: "None"))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.mutedForeground)
    }
}
