import SwiftUI

/// Nightfall: how much shade, from full sun to deep shade.
struct OnboardingProtectionStep: View {
    @Binding var choices: OnboardingChoices
    let stepNumber: Int

    /// In the cards' order.
    static let levels: [ProtectionLevel] = [.off, .standard, .strict]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 10) {
                OnboardingEyebrow(text: "Step \(stepNumber) · Protection")
                Text("How much shade do you want?")
                    .font(.system(size: 40, weight: .black))
                    .tracking(-0.6)
                    .foregroundStyle(OnboardingInk.light)
                    .accessibilityAddTraits(.isHeader)
                Text("The more shade, the less the web sees of you.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingInk.muted)
            }
            .multilineTextAlignment(.center)
            .onboardingFadeUp()
            .padding(.top, 52)

            HStack(spacing: 18) {
                ForEach(Self.levels) { card($0) }
            }
            .padding(.horizontal, 40)
            .padding(.top, 190)
            .onboardingFadeUp(delay: 0.15)

            Text("Change it any time per space in Settings, or per site from the shield in the address bar.")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#B9AEE2"))
                .padding(.top, 488)
        }
        .frame(width: 800, height: 600, alignment: .top)
    }

    private func card(_ level: ProtectionLevel) -> some View {
        let isSelected = choices.protection == level
        return Button {
            choices.protection = level
        } label: {
            VStack(spacing: 12) {
                OmbrePlanet(size: 104, shadow: level.shadeShadow)
                VStack(spacing: 2) {
                    Text(level.shadeTitle)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(OnboardingInk.light)
                    // The name the settings use.
                    Text(level.title.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#B9AEE2"))
                }
                Text(level.shadeSummary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "#F1E4F4") : Color(hex: "#CFC5EE"))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(background(isSelected: isSelected))
            .overlay(alignment: .top) {
                if level == .standard {
                    Text("Recommended")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(OnboardingInk.dark)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Capsule().fill(OnboardingInk.primaryGradient))
                        .offset(y: -12)
                }
            }
            // The chosen card floats.
            .modifier(OnboardingFloat(distance: 5, period: 4, isActive: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: isSelected)
        .accessibilityLabel("\(level.shadeTitle), \(level.title)")
        .accessibilityHint(level.shadeSummary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func background(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            if isSelected {
                shape.fill(LinearGradient(
                    colors: [OnboardingInk.peach.opacity(0.16), Color(hex: "#F06BA8").opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                shape.strokeBorder(OnboardingInk.peach, lineWidth: 2)
            } else {
                shape.fill(Color.white.opacity(0.05))
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .shadow(color: isSelected ? Color(hex: "#FF8F86").opacity(0.25) : .clear, radius: 20)
    }
}

extension ProtectionLevel {
    /// The settings' name.
    var title: String {
        switch self {
        case .standard: "Standard"
        case .strict: "Strict"
        case .off: "Off"
        }
    }

    /// The assistant's name: how much shade.
    var shadeTitle: String {
        switch self {
        case .off: "Sunny"
        case .standard: "Ombre"
        case .strict: "Deep shade"
        }
    }

    var shadeSummary: String {
        switch self {
        case .off: "No blocking. Pages load exactly as their sites made them."
        case .standard: "Blocks ads and trackers. Hides your fingerprint in private windows, like Safari."
        case .strict: "Everything in Ombre, plus fingerprint hiding in every window. A few sites may act up."
        }
    }

    /// The card planet's shadow: none in the sun, the icon's for Ombre.
    var shadeShadow: Double {
        switch self {
        case .off: 0
        case .standard: 1
        case .strict: 1.6
        }
    }
}
