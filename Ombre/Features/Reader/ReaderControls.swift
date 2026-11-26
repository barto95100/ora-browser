import AppKit
import SwiftUI

/// The article's headings (h2, and h3 set in); a click goes there.
struct ReaderContentsView: View {
    let headings: [ReaderArticle.Heading]
    let onSelect: (ReaderArticle.Heading) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(headings) { heading in
                    Button { onSelect(heading) } label: {
                        Text(heading.text)
                            .font(.system(
                                size: heading.level > 2 ? 12 : 13,
                                weight: heading.level > 2 ? .regular : .medium
                            ))
                            .foregroundStyle(heading.level > 2 ? .secondary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, heading.level > 2 ? 16 : 0)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Theme, text size, column width and font of reader mode.
struct ReaderStyleView: View {
    @ObservedObject var settings: ReaderSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(ReaderSettings.Theme.allCases) { theme in
                    themeButton(theme)
                }
            }
            HStack(spacing: 8) {
                Button { settings.makeTextSmaller() } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 40)
                }
                .disabled(!settings.canMakeTextSmaller)
                .help("Smaller Text")
                .accessibilityLabel(String(localized: "Smaller Text"))
                Button { settings.resetTextSize() } label: {
                    Text(verbatim: "\(settings.size)").monospacedDigit().frame(minWidth: 28)
                }
                .help("Default Size")
                Button { settings.makeTextBigger() } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 40)
                }
                .disabled(!settings.canMakeTextBigger)
                .help("Bigger Text")
                .accessibilityLabel(String(localized: "Bigger Text"))
            }
            Picker("Width", selection: $settings.width) {
                ForEach(ReaderSettings.Width.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Font", selection: $settings.font) {
                ForEach(ReaderSettings.Font.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func themeButton(_ theme: ReaderSettings.Theme) -> some View {
        let selected = settings.theme == theme
        return Button { settings.theme = theme } label: {
            VStack(spacing: 4) {
                ZStack {
                    if theme == .automatic {
                        Circle().fill(LinearGradient(
                            colors: [
                                Color(nsColor: ReaderDocument.background(for: .light, isDark: false)),
                                Color(nsColor: ReaderDocument.background(for: .dark, isDark: true))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    } else {
                        Circle().fill(Color(nsColor: ReaderDocument.background(for: theme, isDark: false)))
                    }
                    Circle().strokeBorder(
                        selected ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: selected ? 2.5 : 1
                    )
                }
                .frame(width: 34, height: 34)
                Text(theme.title).font(.system(size: 10))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
