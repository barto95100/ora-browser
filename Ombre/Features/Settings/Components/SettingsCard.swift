import SwiftUI

/// A group of settings, like in System Settings: its title and explanation
/// above a rounded card holding the settings.
struct SettingsCard<Content: View>: View {
    var header: String?
    var description: String?
    /// An edge of this color around the card (red: what cannot be undone).
    var border: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if header != nil || description != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let header {
                        Text(header)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let description {
                        Text(description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardBackground(border: border)
        }
    }
}

private extension View {
    /// White on the light gray window, a lighter shade on the dark one.
    static var settingsCardFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.white
        })
    }
}

extension View {
    /// The background of a settings card: glass with a light edge on
    /// macOS 26, over the window's backdrop; before, a plain card.
    @ViewBuilder
    func settingsCardBackground(border: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.settingsCardRadius, style: .continuous)
        Group {
            if #available(macOS 26, *) {
                ombreGlass(in: shape, rim: true)
            } else {
                plainCardBackground()
            }
        }
        .overlay {
            if let border {
                shape.strokeBorder(border, lineWidth: 1).allowsHitTesting(false)
            }
        }
    }

    /// Rounder with glass, like Apple's.
    private static var settingsCardRadius: CGFloat {
        if #available(macOS 26, *) { return 16 }
        return 12
    }

    private func plainCardBackground() -> some View {
        background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.settingsCardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
    }
}

/// A setting on one line: its name and a short explanation at the left, its
/// control at the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    /// The explanation is a warning (in orange).
    var detailIsWarning = false
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(detailIsWarning ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // Its label is hidden: VoiceOver names it after the row.
            control()
                .accessibilityLabel(Text(title))
        }
    }
}
