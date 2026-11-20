import SwiftUI

/// Light, dark or like the Mac: three thumbnails, the chosen one outlined
/// in the accent color, like System Settings › Appearance.
struct AppearanceSelector: View {
    @Binding var selection: AppAppearance

    private struct Option: Identifiable {
        var id: AppAppearance {
            appearance
        }
        let appearance: AppAppearance
        let imageName: String
        let title: String
    }

    private var options: [Option] {
        [
            .init(appearance: .light, imageName: "appearance-light", title: String(localized: "Light")),
            .init(appearance: .dark, imageName: "appearance-dark", title: String(localized: "Dark")),
            .init(appearance: .system, imageName: "appearance-system", title: String(localized: "Auto"))
        ]
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(options) { opt in
                let isSelected = selection == opt.appearance
                Button {
                    selection = opt.appearance
                } label: {
                    VStack(spacing: 6) {
                        Image(opt.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .padding(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                        lineWidth: 2.5
                                    )
                            )
                        Text(opt.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
