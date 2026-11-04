import SwiftUI

/// Sunset: the Zen spaces become moons around a small planet.
struct OnboardingImportStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            system
                .frame(width: 300, height: 300)
                .position(x: 180, y: 260)
            Text("Your spaces become moons\naround your little planet.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#FFE3D2"))
                .multilineTextAlignment(.center)
                .frame(width: 300)
                .position(x: 180, y: 448)
            column
                .frame(width: 400, height: 448, alignment: .top)
                .offset(x: 360, y: 58)
        }
        .frame(width: 800, height: 600, alignment: .topLeading)
    }

    private var spaces: [ImportedSpace] {
        model.zenSpaces?.spaces ?? []
    }

    // MARK: - Planet and moons

    private var system: some View {
        ZStack {
            OnboardingGlow(size: 220)
            OmbrePlanet(size: 150, shadow: OnboardingNightfall.shadow(for: .importZen))
            Circle()
                .strokeBorder(Color(hex: "#FFD3B0").opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 240, height: 240)
            Circle()
                .strokeBorder(Color(hex: "#FFD3B0").opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 300, height: 300)
            OnboardingClock { time in
                ZStack {
                    ForEach(Array(spaces.prefix(8).enumerated()), id: \.offset) { index, space in
                        moon(space, index: index, time: time)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Every other moon on the outer orbit, which turns the other way.
    private func moon(_ space: ImportedSpace, index: Int, time: TimeInterval) -> some View {
        let isInner = index.isMultiple(of: 2)
        let count = min(spaces.count, 8)
        let onThisOrbit = isInner ? (count + 1) / 2 : count / 2
        let slot = index / 2
        let start = isInner ? -90.0 : 180.0
        let turn = isInner ? time / 18 * 360 : -time / 26 * 360
        let degrees = start + Double(slot) / Double(max(onThisOrbit, 1)) * 360 + turn
        let radius: Double = isInner ? 120 : 150
        let radians = degrees * .pi / 180
        return MoonBadge(space: space, index: index, size: 40)
            .shadow(color: MoonBadge.palette(index).glow.opacity(0.6), radius: 9)
            .opacity(model.choices.importedSpaces.contains(index) ? 1 : 0.35)
            .offset(x: radius * cos(radians), y: radius * sin(radians))
            .animation(.easeInOut(duration: 0.3), value: model.choices.importedSpaces)
    }

    // MARK: - Choices

    private var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingEyebrow(text: "Step \(model.flow.index + 1) · Moving in")
                Text("Bring your spaces from Zen")
                    .font(.system(size: 38, weight: .black))
                    .tracking(-0.5)
                    .foregroundStyle(OnboardingInk.light)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .onboardingFadeUp()
            Text("Essentials become favorites, pinned tabs and folders come along. Open tabs stay in Zen.")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "#FFEDE4"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingFadeUp(delay: 0.15)
            VStack(alignment: .leading, spacing: 16) {
                profilePicker
                if model.isZenRunning {
                    zenIsOpen
                }
            }
            .onboardingFadeUp(delay: 0.15)
            Group {
                if let failure = model.zenFailure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#FFD9C2"))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(spaces.enumerated()), id: \.offset) { index, space in
                                spaceCard(space, index: index)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .onboardingFadeUp(delay: 0.3)
        }
    }

    private var profilePicker: some View {
        HStack(spacing: 10) {
            Text("Profile")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color(hex: "#E2D8FA"))
            Menu {
                ForEach(model.zenProfiles, id: \.self) { profile in
                    Button(title(of: profile)) { model.selectZenProfile(profile) }
                }
            } label: {
                HStack {
                    Text(model.zenProfile.map(title(of:)) ?? "")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(OnboardingInk.light)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(model.zenProfiles.count < 2)
            .accessibilityLabel("Profile")
            .accessibilityValue(model.zenProfile.map(title(of:)) ?? "")
        }
    }

    private func title(of profile: URL) -> String {
        model.zenProfileTitles[profile] ?? profile.lastPathComponent
    }

    private var zenIsOpen: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(OnboardingInk.eyebrow)
                .accessibilityHidden(true)
            Text("Zen is open. Quit it to bring its latest changes.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#FFD9C2"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Reload") { model.reloadZen() }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .controlSize(.small)
                .scaleEffect(0.82)
                .frame(height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OnboardingInk.peach.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingInk.peach.opacity(0.35), lineWidth: 1)
        )
    }

    private func spaceCard(_ space: ImportedSpace, index: Int) -> some View {
        let isOn = model.choices.importedSpaces.contains(index)
        return Toggle(isOn: selection(index)) {
            HStack(spacing: 14) {
                MoonBadge(space: space, index: index, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(OnboardingInk.light)
                    Text(BrowserImportSheet.summary(of: space))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#D8CEF5"))
                }
                Spacer(minLength: 0)
            }
        }
        .toggleStyle(OnboardingCheckboxStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isOn ? MoonBadge.palette(index).glow.opacity(0.55) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isOn)
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

/// A Zen space as a little colored moon, with its emoji or first letter.
struct MoonBadge: View {
    struct Palette {
        let top: Color
        let bottom: Color
        let ink: Color

        var glow: Color {
            bottom
        }
    }

    let space: ImportedSpace
    let index: Int
    let size: CGFloat

    static func palette(_ index: Int) -> Palette {
        let palettes = [
            Palette(top: Color(hex: "#9AD9FF"), bottom: Color(hex: "#5B7BFF"), ink: Color(hex: "#10163A")),
            Palette(top: Color(hex: "#FFE29A"), bottom: Color(hex: "#FFA35B"), ink: Color(hex: "#3A2210")),
            Palette(top: Color(hex: "#B9F5D2"), bottom: Color(hex: "#5FD39A"), ink: Color(hex: "#123A28")),
            Palette(top: Color(hex: "#FFC2DD"), bottom: Color(hex: "#F06BA8"), ink: Color(hex: "#3A1028")),
            Palette(top: Color(hex: "#D9C6FF"), bottom: Color(hex: "#9A6BFF"), ink: Color(hex: "#22124A"))
        ]
        return palettes[index % palettes.count]
    }

    var body: some View {
        let palette = Self.palette(index)
        Text(label)
            .font(.system(size: size * 0.48, weight: .black))
            .foregroundStyle(palette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )))
            .accessibilityHidden(true)
    }

    private var label: String {
        if let emoji = space.emoji, !emoji.isEmpty {
            return emoji
        }
        return space.name.first.map { String($0).uppercased() } ?? "•"
    }
}

/// A round-cornered checkbox in front of the label, the whole row clickable.
struct OnboardingCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? Color(hex: "#FF9F86") : Color.clear)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(configuration.isOn ? 0 : 0.45), lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(OnboardingInk.dark)
                    }
                }
                .frame(width: 18, height: 18)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
