import AppKit
import SwiftUI

/// Dusk: the first space and the window's look, with a live preview. The
/// space's color changes only the preview; the screen keeps its colors.
struct OnboardingSpacesStep: View {
    @ObservedObject var model: OnboardingModel

    static let symbols = [
        "house", "briefcase", "chevron.left.forwardslash.chevron.right", "music.note",
        "gamecontroller", "moon", "heart", "star"
    ]
    /// What VoiceOver says for each symbol.
    static let symbolNames = [
        "house": "Home", "briefcase": "Briefcase", "chevron.left.forwardslash.chevron.right": "Code",
        "music.note": "Music", "gamecontroller": "Game", "moon": "Moon", "heart": "Heart", "star": "Star"
    ]
    /// A row holds 8 tiles in the form's width.
    static let rowLength = 8
    static let emojis = ["🏠", "💼", "🎮", "🌙", "🍿"]
    static let colors: [SpaceColor] = [.orange, .pink, .purple, .blue, .green, .yellow]

    private var look: SpaceLook {
        model.choices.firstSpace
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            form
                .frame(width: 336, alignment: .leading)
                .offset(x: 40, y: 46)
            OnboardingSpacePreview(
                look: look,
                sidebarPosition: model.choices.sidebarPosition,
                appearance: model.choices.appearance
            )
            .modifier(OnboardingFloat(distance: 6, period: 6))
            .frame(width: 350, height: 300)
            .offset(x: 410, y: 88)
            .onboardingFadeUp(delay: 0.15)
            Text("Live preview: every choice shows up here right away.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#D8CEF5"))
                .frame(width: 350)
                .offset(x: 410, y: 404)
            moreSpaces
                .frame(width: 350)
                .offset(x: 410, y: 436)
        }
        .frame(width: 800, height: 600, alignment: .topLeading)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 13) {
            OnboardingEyebrow(text: "Step \(model.flow.index + 1) · Decorate")
            Text("Make it yours")
                .font(.system(size: 38, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(OnboardingInk.light)
                .accessibilityAddTraits(.isHeader)
            Text(model.editsExistingSpace ? "Your space" : "Your first space")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color(hex: "#D8CEF5"))
                .padding(.top, 2)
            TextField(
                "Name",
                text: $model.choices.firstSpace.name,
                prompt: Text("Name").foregroundColor(.white.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(OnboardingInk.light)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .accessibilityLabel(model.editsExistingSpace ? "Your space" : "Your first space")
            HStack(spacing: 6) {
                ForEach(symbolChoices, id: \.self) { symbol in
                    tile(isSelected: look.iconSymbol == symbol, label: Self.symbolNames[symbol] ?? symbol) {
                        model.choices.firstSpace.iconSymbol = symbol
                    } content: {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(emojiChoices, id: \.self) { emoji in
                    tile(isSelected: look.iconSymbol == nil && look.emoji == emoji, label: emoji) {
                        model.choices.firstSpace.emoji = emoji
                        model.choices.firstSpace.iconSymbol = nil
                    } content: {
                        Text(emoji).font(.system(size: 18))
                    }
                }
            }
            HStack(spacing: 9) {
                ForEach(colorChoices) { colorChoice($0) }
            }
            .frame(height: 36)
            HStack(spacing: 14) {
                segmented(
                    [("Left", SidebarPosition.primary), ("Right", SidebarPosition.secondary)],
                    selection: $model.choices.sidebarPosition,
                    label: "Sidebar"
                )
                segmented(
                    [("Auto", AppAppearance.system), ("Light", .light), ("Dark", .dark)],
                    selection: $model.choices.appearance,
                    label: "Appearance"
                )
            }
        }
        .onboardingFadeUp()
    }

    /// The space's look when the assistant opened: its own symbol, emoji
    /// and color stay offered even once another is picked.
    private var own: SpaceLook {
        model.initial.firstSpace
    }

    private var symbolChoices: [String] {
        Self.choices(Self.symbols, keeping: own.iconSymbol)
    }

    private var emojiChoices: [String] {
        Self.choices(Self.emojis, keeping: own.emoji == ContainerConstants.defaultEmoji ? nil : own.emoji)
    }

    private var colorChoices: [SpaceColor] {
        Self.choices(Self.colors, keeping: own.color)
    }

    /// The offered choices, plus `own` when it isn't one of them, still in
    /// one row: it takes the last place of a full row.
    static func choices<Choice: Equatable>(_ offered: [Choice], keeping own: Choice?) -> [Choice] {
        guard let own, !offered.contains(own) else { return offered }
        return Array(offered.prefix(rowLength - 1)) + [own]
    }

    /// Selected: a white outline.
    private func tile(
        isSelected: Bool,
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(isSelected ? Color.white : Color(hex: "#D9CFF5"))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.2 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 1 : 0.14), lineWidth: isSelected ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorChoice(_ color: SpaceColor) -> some View {
        let isSelected = look.color == color
        return Button {
            model.choices.firstSpace.color = color
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: isSelected ? 34 : 28, height: isSelected ? 34 : 28)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: isSelected ? 3 : 0))
                .shadow(color: isSelected ? color.color.opacity(0.85) : .clear, radius: 7)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A row of choices; the chosen one is white.
    private func segmented<Value: Hashable>(
        _ options: [(String, Value)],
        selection: Binding<Value>,
        label: String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.1) { title, value in
                let isSelected = selection.wrappedValue == value
                Button {
                    selection.wrappedValue = value
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .black : .heavy))
                        .foregroundStyle(isSelected ? Color(hex: "#1A1230") : Color(hex: "#D9CFF5"))
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Color(hex: "#FFFBF7") : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .animation(.easeInOut(duration: 0.2), value: selection.wrappedValue)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: - More spaces

    private var moreSpaces: some View {
        HStack(spacing: 8) {
            Text("More spaces")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color(hex: "#D8CEF5"))
            ForEach(SpaceTemplate.allCases) { templateChip($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func templateChip(_ template: SpaceTemplate) -> some View {
        let isOn = model.choices.templates.contains(template)
        let otherTemplates = model.choices.templates.subtracting([template]).map(\.look.name)
        let isAvailable = SpaceTemplate.isAvailable(template, takenNames: model.takenNames + otherTemplates)
        return Button {
            if isOn {
                model.choices.templates.remove(template)
            } else {
                model.choices.templates.insert(template)
            }
        } label: {
            Text((isOn ? "✓ " : "+ ") + template.look.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isOn ? Color(hex: "#1A1230") : OnboardingInk.light)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? Color(hex: "#FFFBF7") : .clear))
                .overlay(
                    Capsule().strokeBorder(
                        Color.white.opacity(isOn ? 0 : 0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !isAvailable)
        .opacity(!isOn && !isAvailable ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Preview

/// A small Ombre window: the sidebar on its side in the space's color, the
/// space's icon and name, a light or dark page.
struct OnboardingSpacePreview: View {
    let look: SpaceLook
    let sidebarPosition: SidebarPosition
    let appearance: AppAppearance

    /// Without a color, the planet's violet.
    static let defaultAccent = Color(hex: "#A57CFF")

    private var accent: Color {
        look.color?.color ?? Self.defaultAccent
    }

    /// The accent deep in the night, for the sidebar.
    private var deep: Color {
        Self.deep(accent)
    }

    static func deep(_ accent: Color) -> Color {
        accent.mix(with: Color(hex: "#1A1230"), by: 0.72)
    }

    /// Like the app: a space with a theme is always dark.
    private var isDark: Bool {
        if look.theme != nil { return true }
        switch appearance {
        case .system:
            // The assistant's window is drawn dark whatever the system
            // appearance: ask the app.
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .light: return false
        case .dark: return true
        }
    }

    var body: some View {
        let sidebarOnLeft = sidebarPosition == .primary
        ZStack(alignment: sidebarOnLeft ? .leading : .trailing) {
            page
                .padding(sidebarOnLeft ? .leading : .trailing, 112)
            sidebar(onLeft: sidebarOnLeft)
                .frame(width: 112)
        }
        // Moving the sidebar fades rather than slides.
        .id(sidebarOnLeft)
        .transition(.opacity)
        .frame(width: 350, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(accent.opacity(0.16))
                .padding(-6)
        )
        .shadow(color: Color(hex: "#0B0728").opacity(0.5), radius: 30, y: 30)
        .animation(.easeInOut(duration: 0.45), value: look)
        .animation(.easeInOut(duration: 0.45), value: isDark)
        .animation(.easeInOut(duration: 0.45), value: sidebarPosition)
        .accessibilityElement()
        .accessibilityLabel("Live preview of your space")
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Capsule().fill(isDark ? Color(hex: "#3A3557") : Color(hex: "#FFFBF7"))
                    .frame(height: 18)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isDark ? Color(hex: "#2A2643") : Color(hex: "#ECE7E0"))
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 9) {
                        line(width: proxy.size.width * 0.7, height: 14, primary: true)
                        line(width: proxy.size.width * 0.92, height: 8, primary: false)
                        line(width: proxy.size.width * 0.86, height: 8, primary: false)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(hex: "#FFD3B0"), Color(hex: "#F2A4C6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 96)
                    }
                }
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color(hex: "#1C1930") : Color(hex: "#F4F1EC"))
    }

    private func line(width: CGFloat, height: CGFloat, primary: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isDark
                ? Color(hex: primary ? "#4A4468" : "#3A3557")
                : Color(hex: primary ? "#D8D1C6" : "#E5DFD6"))
            .frame(width: width, height: height)
    }

    private func sidebar(onLeft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if !onLeft { Spacer(minLength: 0) }
                ForEach(["#FF6B6B", "#F2C94C", "#5FD39A"], id: \.self) { color in
                    Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 6) {
                spaceIcon(size: 20, corner: 6, iconSize: 11)
                Text(look.trimmedName.isEmpty ? " " : look.trimmedName)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(hex: "#FFFBF7"))
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.16)).frame(height: 22)
                }
            }
            RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.6)).frame(height: 18)
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)).frame(height: 18)
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)).frame(height: 18)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                spaceIcon(size: 22, corner: 11, iconSize: 11)
                    .shadow(color: accent.opacity(0.45), radius: 5)
                Circle().fill(Color.white.opacity(0.3)).frame(width: 8, height: 8)
                Circle().fill(Color.white.opacity(0.3)).frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(
            colors: [deep, isDark ? Color(hex: "#120E26") : deep],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    private func spaceIcon(size: CGFloat, corner: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(accent)
            if let symbol = look.iconSymbol {
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(Color(hex: "#1A1230"))
            } else {
                Text(look.emoji).font(.system(size: iconSize + 1))
            }
        }
        .frame(width: size, height: size)
    }
}
