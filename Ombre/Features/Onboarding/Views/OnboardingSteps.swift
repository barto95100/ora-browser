import SwiftUI

/// A step's title and text, the same on every screen. They rise into place
/// when the screen appears (they fade in only, with Reduce Motion).
struct OnboardingHeader: View {
    let title: String
    var text: String?
    /// The welcome screen waits for its logo.
    var delay: Duration = .zero

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(theme.foreground)
            if let text {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 520)
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 10)
        .task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { isShown = true }
        }
    }
}

// MARK: - 1. Welcome

struct OnboardingWelcomeStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            OmbreAnimatedLogo(size: 128)
            OnboardingHeader(
                title: "Welcome to Ombre",
                text: "A calm, private browser for your Mac.",
                delay: LogoStage.duration(reduceMotion: reduceMotion)
            )
            Spacer()
        }
    }
}

// MARK: - 2. Import

struct OnboardingImportStep: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                title: "Bring your spaces from Zen",
                text: "Ombre imports your Zen spaces with their Essentials (as favorites), pinned tabs and folders. "
                    + "Open tabs stay in Zen."
            )

            if model.zenProfiles.count > 1 {
                Picker("Profile:", selection: profileBinding) {
                    ForEach(model.zenProfiles, id: \.self) { profile in
                        Text(model.zenProfileTitles[profile] ?? profile.lastPathComponent).tag(profile)
                    }
                }
                .frame(maxWidth: 420)
            }

            if model.isZenRunning {
                HStack(spacing: 8) {
                    Label(
                        "Zen is open. Quit it to include its latest changes.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    OmbreButton(label: "Reload", variant: .outline, size: .sm) { model.reloadZen() }
                }
            }

            if let failure = model.zenFailure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let spaces = model.zenSpaces {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(spaces.spaces.enumerated()), id: \.offset) { index, space in
                            Toggle(isOn: selection(index)) {
                                HStack(spacing: 8) {
                                    Text(space.emoji ?? "•")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(space.name).foregroundColor(theme.foreground)
                                        Text(BrowserImportSheet.summary(of: space))
                                            .font(.caption)
                                            .foregroundColor(theme.mutedForeground)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 420, maxHeight: 260)
            }
            Spacer(minLength: 0)
        }
    }

    private var profileBinding: Binding<URL> {
        Binding(
            get: { model.zenProfile ?? model.zenProfiles[0] },
            set: { model.selectZenProfile($0) }
        )
    }

    private func selection(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { model.choices.importedSpaces.contains(index) },
            set: { isOn in
                if isOn {
                    model.choices.importedSpaces.insert(index)
                } else {
                    model.choices.importedSpaces.remove(index)
                }
            }
        )
    }
}

// MARK: - 3. Spaces and appearance

struct OnboardingSpacesStep: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(title: "Make it yours")
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Sidebar") {
                        Picker("Sidebar", selection: $model.choices.sidebarPosition) {
                            Label("Left", systemImage: "sidebar.left").tag(SidebarPosition.primary)
                            Label("Right", systemImage: "sidebar.right").tag(SidebarPosition.secondary)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    section("Appearance") {
                        Picker("Appearance", selection: $model.choices.appearance) {
                            ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    section("Add more spaces") {
                        HStack(spacing: 8) {
                            ForEach(SpaceTemplate.allCases) { templateChip($0) }
                        }
                        Text("You can add spaces later from the bottom of the sidebar.")
                            .font(.caption)
                            .foregroundColor(theme.mutedForeground)
                    }
                }
                .frame(width: 230)

                section(model.editsExistingSpace ? "Your space" : "Your first space") {
                    OmbreInput(text: $model.choices.firstSpace.name, placeholder: "Name (work, streaming, finance...)")
                    SpaceLookFields(look: $model.choices.firstSpace)
                }
                .frame(width: 400)
            }
            Spacer(minLength: 0)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.mutedForeground)
            content()
        }
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
            Label(template.look.name, systemImage: isOn ? "checkmark" : "plus")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(isOn ? .white : theme.foreground)
                .background(
                    isOn ? template.look.color?.color ?? theme.accent : theme.mutedBackground,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !isAvailable)
        .opacity(!isOn && !isAvailable ? 0.4 : 1)
    }
}

// MARK: - 4. Protection

struct OnboardingProtectionStep: View {
    @Binding var choices: OnboardingChoices
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(title: "Choose your protection")
            VStack(spacing: 10) {
                ForEach(ProtectionLevel.allCases) { card($0) }
            }
            .frame(maxWidth: 480)
            Text("Change it for a space in Settings › Spaces, or for a site from the shield in the address bar.")
                .font(.caption)
                .foregroundColor(theme.mutedForeground)
            Spacer(minLength: 0)
        }
    }

    private func card(_ level: ProtectionLevel) -> some View {
        let isSelected = choices.protection == level
        return Button {
            choices.protection = level
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? theme.accent : theme.mutedForeground)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(level.title).font(.system(size: 14, weight: .semibold))
                        if level == .standard {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.mutedBackground, in: Capsule())
                        }
                    }
                    Text(level.summary)
                        .font(.system(size: 12))
                        .foregroundColor(theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(theme.foreground)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.mutedBackground : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ProtectionLevel {
    var title: String {
        switch self {
        case .standard: "Standard"
        case .strict: "Strict"
        case .off: "Off"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            "Blocks ads and trackers with AdGuard's lists. Fingerprinting protection in private windows, like Safari."
        case .strict:
            "Everything in Standard, plus fingerprinting protection in every window. "
                + "A few sites may behave differently."
        case .off:
            "Pages load as their sites made them."
        }
    }
}

// MARK: - 5. Default browser

struct OnboardingDefaultBrowserStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            OnboardingHeader(
                title: "Make Ombre your default browser?",
                text: "Links you open in other apps will open in Ombre."
            )
            Spacer()
        }
    }
}

// MARK: - 6. Ready

struct OnboardingReadyStep: View {
    @Environment(\.theme) private var theme

    private let shortcuts: [(KeyboardShortcutDefinition, String)] = [
        (KeyboardShortcuts.Tabs.new, "Open a tab or search"),
        (KeyboardShortcuts.App.toggleSidebar, "Show or hide the sidebar"),
        (KeyboardShortcuts.Tabs.pin, "Pin the current tab"),
        (KeyboardShortcuts.Window.newPrivate, "Open a private window")
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            OnboardingHeader(title: "You're all set")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shortcuts, id: \.0.id) { shortcut, text in
                    HStack(spacing: 14) {
                        Text(shortcut.display)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(minWidth: 56)
                            .padding(.vertical, 5)
                            .background(theme.mutedBackground, in: RoundedRectangle(cornerRadius: 6))
                        Text(text)
                            .foregroundColor(theme.foreground)
                    }
                }
            }
            Spacer()
        }
    }
}
