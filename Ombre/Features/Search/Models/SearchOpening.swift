import Foundation

/// What a search opens: the address, and the question to paste when the
/// site ignores the one in its address (Gemini opens with an empty field).
struct SearchOpening: Equatable {
    let url: URL
    /// Nil when the address carries the question.
    let questionToPaste: String?

    /// `query` sent to an engine whose address is `template`; nil unless it
    /// makes a web address.
    static func make(template: String, acceptsQuery: Bool, query: String) -> SearchOpening? {
        if acceptsQuery {
            return SearchEngineService.searchURL(template: template, query: query)
                .map { SearchOpening(url: $0, questionToPaste: nil) }
        }
        guard let url = pageURL(template: template) else { return nil }
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchOpening(url: url, questionToPaste: question.isEmpty ? nil : question)
    }

    /// The engine's page without the search: the parameters holding it are
    /// dropped, and a path holding it stops before it.
    static func pageURL(template: String) -> URL? {
        let marker = "ombre-query-marker" // no translation
        let marked = template.replacingOccurrences(of: "{query}", with: marker) // no translation
        guard var components = URLComponents(string: marked) else { return nil }
        let items = components.queryItems?.filter {
            !$0.name.contains(marker) && !($0.value?.contains(marker) ?? false)
        }
        components.queryItems = (items?.isEmpty ?? true) ? nil : items
        if components.fragment?.contains(marker) == true { components.fragment = nil }
        if let range = components.path.range(of: marker) {
            let before = components.path[..<range.lowerBound]
            let lastSlash = before.lastIndex(of: "/")
            components.path = lastSlash.map { String(before[...$0]) } ?? "/"
        }
        guard let url = components.url, !url.absoluteString.contains(marker),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return nil }
        return url
    }
}
