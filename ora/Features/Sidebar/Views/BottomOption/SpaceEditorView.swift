import SwiftData
import SwiftUI

/// Creates or edits a space: name, icon (a symbol or an emoji), color and
/// theme.
/// Editing shows the changes right away; Cancel puts the space back as it was.
struct SpaceEditorView: View {
    /// The space edited, or nil to create one.
    let container: TabContainer?
    let dismiss: () -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var dialogManager: DialogManager

    @State private var name = ""
    @State private var emoji = ContainerConstants.defaultEmoji
    @State private var iconSymbol: String?
    @State private var color: SpaceColor?
    @State private var spaceTheme: SpaceTheme?
    @State private var isEmojiMode = false
    @State private var isEmojiPickerOpen = false
    /// The space before editing, put back by Cancel.
    @State private var original: SpaceLook?
    @FocusState private var isNameFocused: Bool

    private let iconColumns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(container == nil ? "New Space" : "Edit Space")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.foreground)

            OraInput(text: $name, placeholder: "Name (work, streaming, finance...)", onSubmit: save)
                .focused($isNameFocused)

            iconSection
            colorSection
            themeSection

            HStack {
                if let container, tabManager.canDeleteSpace(container) {
                    Button("Delete…", action: confirmDelete)
                        .buttonStyle(.plain)
                        .foregroundColor(theme.destructive)
                }
                Spacer()
                OraButton(label: "Cancel", variant: .secondary, keyboardShortcut: "esc", action: cancel)
                OraButton(label: "OK", isDisabled: trimmedName.isEmpty, keyboardShortcut: "return", action: save)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(theme.popoverBackground)
        .cornerRadius(14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear(perform: setUp)
        // Editing: the space shows its new look right away.
        .onChange(of: iconSymbol) { applyLive() }
        .onChange(of: color) { applyLive() }
        .onChange(of: spaceTheme) { applyLive() }
        .onChange(of: emoji) { applyLive() }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Icon

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Icon")
                Spacer()
                Button(isEmojiMode ? "Symbols" : "Emoji") {
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
        let isSelected = iconSymbol == symbol
        return Button {
            iconSymbol = symbol
        } label: {
            Image(systemName: symbol ?? "nosign")
                .font(.system(size: 15))
                .foregroundColor(isSelected ? color?.color ?? theme.foreground : theme.mutedForeground)
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? theme.mutedBackground : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol == nil ? "No symbol (emoji)" : symbol ?? "")
    }

    private var emojiPicker: some View {
        HStack(spacing: 10) {
            Button {
                isEmojiPickerOpen.toggle()
            } label: {
                Text(emoji)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(theme.mutedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEmojiPickerOpen, arrowEdge: .bottom) {
                EmojiPickerView { selected in
                    emoji = selected
                    iconSymbol = nil
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
                sectionTitle("Color")
                Spacer()
                Text(color?.title ?? "None")
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
        let isSelected = color == choice
        return Button {
            color = choice
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
        .help(choice?.title ?? "None")
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Theme")
                Spacer()
                Text(spaceTheme?.title ?? "None")
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
        let isSelected = spaceTheme == choice
        return Button {
            spaceTheme = choice
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
        .help(choice?.title ?? "None")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.mutedForeground)
    }

    // MARK: - Actions

    private func setUp() {
        if let container {
            name = container.name
            emoji = container.emoji
            iconSymbol = container.iconSymbol
            color = container.spaceColor
            spaceTheme = container.spaceTheme
            original = SpaceLook(
                name: container.name,
                emoji: container.emoji,
                iconSymbol: container.iconSymbol,
                color: container.spaceColor,
                theme: container.spaceTheme
            )
        }
        isEmojiMode = iconSymbol == nil && emoji != ContainerConstants.defaultEmoji
        isNameFocused = true
    }

    private func applyLive() {
        guard let container else { return }
        tabManager.updateSpace(
            container,
            name: container.name,
            emoji: emoji,
            iconSymbol: iconSymbol,
            color: color,
            theme: spaceTheme
        )
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let container {
            tabManager.updateSpace(
                container,
                name: trimmedName,
                emoji: emoji,
                iconSymbol: iconSymbol,
                color: color,
                theme: spaceTheme
            )
        } else {
            tabManager.createSpace(
                name: trimmedName,
                emoji: emoji,
                iconSymbol: iconSymbol,
                color: color,
                theme: spaceTheme
            )
        }
        dismiss()
    }

    private func cancel() {
        if let container, let original {
            tabManager.updateSpace(
                container,
                name: original.name,
                emoji: original.emoji,
                iconSymbol: original.iconSymbol,
                color: original.color,
                theme: original.theme
            )
        }
        dismiss()
    }

    private func confirmDelete() {
        guard let container else { return }
        cancel()
        dialogManager.confirm(
            title: "Delete \"\(container.name)\"?",
            message: "All tabs in this space will be permanently removed.",
            icon: .spaceCards,
            confirmLabel: "Delete",
            variant: .destructive
        ) {
            tabManager.deleteContainer(container)
        }
    }
}

/// Name, emoji, symbol and color of a space.
private struct SpaceLook {
    let name: String
    let emoji: String
    let iconSymbol: String?
    let color: SpaceColor?
    let theme: SpaceTheme?
}

extension TabManager {
    /// The last space cannot be deleted.
    func canDeleteSpace(_ container: TabContainer) -> Bool {
        let count = (try? modelContext.fetchCount(FetchDescriptor<TabContainer>())) ?? 0
        return count > 1
    }
}
