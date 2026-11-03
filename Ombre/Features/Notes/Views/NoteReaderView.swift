import AppKit
import SwiftUI

/// A note read, Markdown rendered: titles, lists, tasks (a click checks
/// them), quotes, code; bold, italic, code and links within lines.
struct NoteReaderView: View {
    let markdown: String
    /// The note's folder, where its images are.
    var folder: URL?
    /// Opens the page of a capture (Peek); a new tab by default.
    var openPage: ((URL) -> Void)?
    let onToggleTask: (Int) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(NoteMarkdown.blocks(markdown).enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private func view(for block: NoteMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(.system(size: [24, 20, 17, 15, 14, 13][min(level, 6) - 1], weight: .semibold))
                .padding(.top, level == 1 ? 4 : 2)
        case let .task(line, isDone, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    onToggleTask(line)
                } label: {
                    Image(systemName: isDone ? "checkmark.square.fill" : "square")
                        .foregroundColor(isDone ? theme.accent : theme.mutedForeground)
                }
                .buttonStyle(.plain)
                inline(text)
                    .strikethrough(isDone)
                    .foregroundColor(isDone ? theme.mutedForeground : theme.foreground)
            }
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundColor(theme.mutedForeground)
                inline(text)
            }
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundColor(theme.mutedForeground).monospacedDigit()
                inline(text)
            }
        case let .quote(text):
            inline(text)
                .foregroundColor(theme.mutedForeground)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.mutedForeground.opacity(0.4)).frame(width: 3)
                }
        case let .code(text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(theme.mutedBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .rule:
            Divider().padding(.vertical, 4)
        case let .image(alt, path, link):
            NoteImageView(
                url: folder.map { $0.appendingPathComponent(path) } ?? URL(fileURLWithPath: path),
                alt: alt,
                page: link.flatMap(URL.init(string:)),
                openPage: openPage
            )
        case let .paragraph(text):
            inline(text)
        }
    }

    /// Bold, italic, code and links of a line; bare addresses are links too.
    /// (No text selection: a selectable `Text` swallows the link clicks.)
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return Text(text)
        }
        Self.linkBareAddresses(in: &attributed)
        return Text(attributed)
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func linkBareAddresses(in attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        let matches = linkDetector?.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) ?? []
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: attributed),
                  attributed[range].runs.allSatisfy({ $0.link == nil })
            else { continue }
            attributed[range].link = url
        }
    }
}

/// An image of a note. A click goes back to the page of a capture, or opens
/// the image (Preview); both are in its menu.
private struct NoteImageView: View {
    let url: URL
    let alt: String
    let page: URL?
    let openPage: ((URL) -> Void)?
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    private func open(_ page: URL) {
        if let openPage { openPage(page) } else { openURL(page) }
    }

    private var helpText: String {
        if let page { return "Open \(page.host() ?? page.absoluteString)" }
        return alt.isEmpty ? url.lastPathComponent : alt
    }

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(image.size.width, 900), alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.foreground.opacity(0.08), lineWidth: 1)
                )
                .onTapGesture {
                    if let page { open(page) } else { NSWorkspace.shared.open(url) }
                }
                .contextMenu {
                    if let page {
                        Button("Open Page") { open(page) }
                    }
                    Button("Open Image") { NSWorkspace.shared.open(url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .help(helpText)
        } else {
            Label(alt.isEmpty ? url.lastPathComponent : alt, systemImage: "photo")
                .foregroundColor(theme.mutedForeground)
        }
    }
}
