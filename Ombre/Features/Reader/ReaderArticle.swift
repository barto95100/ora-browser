import Foundation

/// An article as reader mode shows it (see `ReaderScript`).
struct ReaderArticle: Equatable {
    let title: String
    let byline: String?
    let site: String
    let published: Date?
    let language: String?
    let isRightToLeft: Bool
    /// Rebuilt by the script from a short list of tags: no style, script or frame.
    let html: String
    /// The same, for a note.
    let markdown: String
    /// Its images' addresses, in order, as the script wrote them (and the
    /// Markdown has them).
    let images: [String]
    let words: Int
    /// Its h2 and h3, for the contents (each with an anchor in `html`).
    let headings: [Heading]
    /// The page it comes from: the base of its addresses.
    let pageURL: URL

    init?(_ value: Any?, pageURL: URL) {
        guard let value = value as? [String: Any],
              let html = value["html"] as? String, !html.isEmpty,
              let markdown = value["markdown"] as? String
        else { return nil }
        let title = (value["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.title = title ?? pageURL.host() ?? pageURL.absoluteString
        byline = (value["byline"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        site = (value["site"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? pageURL.host() ?? ""
        published = (value["published"] as? String).flatMap(Self.date)
        language = (value["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        isRightToLeft = (value["dir"] as? String)?.lowercased() == "rtl"
        self.html = html
        self.markdown = markdown
        images = value["images"] as? [String] ?? []
        headings = (value["headings"] as? [[String: Any]] ?? []).compactMap(Heading.init)
        words = (value["words"] as? Int) ?? (value["words"] as? Double).map { Int($0) } ?? 0
        self.pageURL = pageURL
    }

    struct Heading: Equatable, Identifiable {
        /// 2 or 3.
        let level: Int
        let text: String
        /// Its anchor in the article ("ombre-heading-1"), made by the script.
        let id: String

        init?(_ value: [String: Any]) {
            guard let text = value["text"] as? String, !text.isEmpty,
                  let id = value["id"] as? String, id.hasPrefix("ombre-heading-")
            else { return nil }
            level = (value["level"] as? Int) ?? (value["level"] as? Double).map { Int($0) } ?? 2
            self.text = text
            self.id = id
        }
    }

    /// The contents are offered from three headings.
    var hasContents: Bool {
        headings.count >= 3
    }

    /// Minutes to read it, at about 230 words a minute.
    var minutes: Int {
        max(1, Int((Double(words) / 230).rounded()))
    }

    /// "Author · 12 March 2026 · 5 min".
    var details: String {
        var parts: [String] = []
        if let byline { parts.append(byline) }
        if let published { parts.append(published.formatted(date: .long, time: .omitted)) }
        parts.append(String(localized: "\(minutes) min read"))
        return parts.joined(separator: " · ")
    }

    static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withFullDate]
        return full.date(from: String(text.prefix(10)))
    }
}
