import CoreGraphics
import Foundation

/// Where a capture was taken in its page: the words at that place, kept in
/// the capture's link as a text fragment (`#:~:text=…`), so the page opens
/// scrolled there (and in Safari too), the words highlighted.
enum PageAnchor {
    /// The words of the page at `point` (CSS pixels of the viewport; its
    /// center when nil), as a JSON-free string, or "" when none.
    static func wordsScript(at point: CGPoint?) -> String {
        let left = point.map { "\($0.x)" } ?? "innerWidth / 2"
        let top = point.map { "\($0.y)" } ?? "innerHeight / 2"
        return """
        (() => {
            document.getElementById('ora-capture-shield')?.remove();
            const x = \(left), y = \(top);
            let text = '';
            const range = document.caretRangeFromPoint && document.caretRangeFromPoint(x, y);
            if (range && range.startContainer.nodeType === Node.TEXT_NODE) {
                text = range.startContainer.textContent;
            }
            if (!text.trim()) {
                let el = document.elementFromPoint(x, y);
                while (el && !(el.innerText || '').trim()) el = el.parentElement;
                text = el ? el.innerText : '';
            }
            return text;
        })();
        """
    }

    /// The first words of `text`, enough to find the place again.
    static func excerpt(_ text: String, words: Int = 8) -> String {
        text.split(whereSeparator: \.isWhitespace).prefix(words).joined(separator: " ")
    }

    /// The page's address leading to `text` (unchanged without it).
    static func url(_ page: URL, scrolledTo text: String) -> URL {
        let words = excerpt(text)
        guard !words.isEmpty, page.scheme?.hasPrefix("http") == true else { return page }
        // Text directives reserve "-", "&" and ","; "(" and ")" would end
        // the Markdown link of the note.
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~!*'"
        )
        guard let encoded = words.addingPercentEncoding(withAllowedCharacters: allowed) else { return page }
        let base = page.absoluteString.components(separatedBy: ":~:").first ?? page.absoluteString
        let separator = base.contains("#") ? ":~:text=" : "#:~:text="
        return URL(string: base + separator + encoded) ?? page
    }
}
