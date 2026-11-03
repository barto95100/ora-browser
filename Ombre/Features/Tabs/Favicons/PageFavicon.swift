import Foundation

/// An icon the page declares with `<link rel="icon" …>` (or an Apple touch icon).
struct PageIconCandidate: Decodable, Equatable {
    let href: String
    let rel: String
    let sizes: String
    let type: String
}

/// Sent by the page script when the page's declared icons change.
/// The page URL it also sends is ignored: the web view's own URL is trusted instead.
struct PageFaviconMessage: Decodable {
    let icons: [PageIconCandidate]
}

/// Picks the icon to show for a page among the ones it declares, like Safari:
/// the page's own icons first, `/favicon.ico` as the last resort.
enum PageFaviconSelector {
    /// Pixel size wanted for the sidebar: 16 pt at 2x.
    static let preferredSize = 32

    /// Icon URLs to try, best first.
    static func orderedIconURLs(from candidates: [PageIconCandidate], pageURL: URL) -> [URL] {
        let ranked = candidates
            .compactMap { candidate -> (url: URL, score: Int)? in
                guard let url = URL(string: candidate.href, relativeTo: pageURL)?.absoluteURL,
                      isFetchable(url)
                else { return nil }
                return (url, score(candidate, url: url))
            }
            .sorted { $0.score < $1.score }
            .map(\.url)

        var urls: [URL] = []
        for url in ranked where !urls.contains(url) {
            urls.append(url)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL,
           ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
           !urls.contains(fallback)
        {
            urls.append(fallback)
        }
        return urls
    }

    /// Lower is better.
    static func score(_ candidate: PageIconCandidate, url: URL) -> Int {
        let sizes = parsedSizes(candidate.sizes)
        var score = if let fitting = sizes.filter({ $0 >= preferredSize }).min() {
            fitting - preferredSize // 32 → 0, 48 → 16, 180 → 148
        } else if let largest = sizes.max() {
            1000 + preferredSize - largest // Too small (16 → 1016).
        } else {
            500 // Size not declared.
        }

        // Plain icons first: touch icons are made for home screens (padding,
        // opaque background), SVG may not render everywhere.
        if candidate.rel.contains("apple-touch-icon") {
            score += 600
        }
        if candidate.type.lowercased().contains("svg") || url.pathExtension.lowercased() == "svg" {
            score += 300
        }
        return score
    }

    /// "16x16 32x32" → [16, 32]; "any" or garbage → [].
    static func parsedSizes(_ sizes: String) -> [Int] {
        sizes
            .lowercased()
            .split(separator: " ")
            .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
    }

    private static func isFetchable(_ url: URL) -> Bool {
        ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "")
    }
}
