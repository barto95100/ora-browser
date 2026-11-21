import Foundation

/// "This address → this space" (Settings › Address Rules), like Arc's Air
/// Traffic Control: links from other apps, and the new tabs a page opens,
/// go to the rule's space. Pure: what matches and which rule wins.
struct AddressRule: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// The domain only (`hacf.fr`, and `www.hacf.fr`).
        case domain
        /// The domain and all its subdomains (`*.sccnf.fr`, `sccnf.fr` too).
        case domainAndSubdomains
        /// Addresses that start so (`github.com/barto95100`).
        case prefix

        var title: String {
            switch self {
            case .domain: String(localized: "Domain")
            case .domainAndSubdomains: String(localized: "Domain and Subdomains")
            case .prefix: String(localized: "Address Starting With")
            }
        }
    }

    var id = UUID()
    var kind: Kind
    /// Normalized (`AddressRule.normalized`): a host for the domains, a host
    /// and a path for a prefix; lowercased, without scheme nor `www.`.
    var pattern: String
    var spaceID: UUID

    /// What the rule shows: `*.sccnf.fr`, `hacf.fr`, `github.com/barto95100…`.
    var display: String {
        switch kind {
        case .domain: pattern
        case .domainAndSubdomains: "*.\(pattern)"
        case .prefix: "\(pattern)…"
        }
    }

    /// The rule's domain alone, for the log (never the rest of a prefix).
    var domain: String {
        String(pattern.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
    }
}

extension AddressRule {
    /// A rule from what was typed: `*.sccnf.fr` (subdomains), an address
    /// with a path or a query (a prefix), else a domain, with its subdomains
    /// when `includesSubdomains` (never for an IP address). Nil when nothing
    /// usable was typed. The domain is lowercased, the path kept as typed.
    static func parse(_ input: String, includesSubdomains: Bool, spaceID: UUID) -> AddressRule? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var kind: Kind = includesSubdomains ? .domainAndSubdomains : .domain
        if text.hasPrefix("*.") {
            text.removeFirst(2)
            kind = .domainAndSubdomains
        }
        guard let pattern = normalized(text) else { return nil }
        if pattern.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            kind = .prefix
        } else if kind == .domainAndSubdomains, isIPAddress(pattern) {
            kind = .domain
        }
        return AddressRule(kind: kind, pattern: pattern, spaceID: spaceID)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        host.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// `https://www.Example.com/Path/` → `example.com/Path/`: no scheme, no
    /// `www.`, the host lowercased, the rest kept; a trailing `/` alone goes.
    /// Nil without a host.
    static func normalized(_ text: String) -> String? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = rest.range(of: "://") {
            rest = String(rest[range.upperBound...])
        }
        let hostEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        guard let host = cleanHost(String(rest[..<hostEnd])) else { return nil }
        var path = String(rest[hostEnd...])
        // `example.com?a` is written `example.com/?a` by the web.
        if path.hasPrefix("?") || path.hasPrefix("#") { path = "/" + path }
        if path == "/" { path = "" }
        return host + path
    }

    /// The domain of an address's host part: lowercased, without port,
    /// sign-in part, `www.` nor the root's dot. Nil for what no web address
    /// has (no dot, a space, `*`…), and for a domain with accents unless
    /// macOS gives its punycode (else a rule that would never match).
    private static func cleanHost(_ text: String) -> String? {
        var host = text.lowercased()
        if let signIn = host.lastIndex(of: "@") { host = String(host[host.index(after: signIn)...]) }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix("."), !host.hasSuffix("..") { host.removeLast() }
        guard !host.isEmpty, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        if !host.allSatisfy(\.isASCII) {
            guard let encoded = URL(string: "https://\(host)")?.host(percentEncoded: true)?.lowercased(),
                  encoded.allSatisfy(\.isASCII), !encoded.contains("%")
            else { return nil }
            host = encoded
        }
        guard host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
        return host
    }

    /// Whether the rule takes `url` (http and https only).
    func matches(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let address = Self.normalized(url.absoluteString)
        else { return false }
        let host = String(address.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        switch kind {
        case .domain:
            return host == pattern
        case .domainAndSubdomains:
            return host == pattern || host.hasSuffix("." + pattern)
        case .prefix:
            guard address.hasPrefix(pattern) else { return false }
            // `example.com/doc` takes `example.com/doc/a`, not `example.com/docs`.
            let next = address.dropFirst(pattern.count).first
            return pattern.hasSuffix("/") || next == nil || next == "/" || next == "?" || next == "#"
        }
    }

    /// How precise the rule is: a prefix over a domain, a domain over its
    /// subdomains, and the longer the more precise.
    var precision: Int {
        switch kind {
        case .prefix: 3_000_000 + pattern.count
        case .domain: 2_000_000 + pattern.count
        case .domainAndSubdomains: 1_000_000 + pattern.count
        }
    }

    /// The rule for `url`: the most precise of those that take it, among the
    /// spaces that still exist (`spaceIDs`); the first of equals.
    static func rule(for url: URL, in rules: [AddressRule], spaceIDs: Set<UUID>) -> AddressRule? {
        var best: AddressRule?
        for rule in rules where spaceIDs.contains(rule.spaceID) && rule.matches(url) {
            if best == nil || rule.precision > best?.precision ?? 0 { best = rule }
        }
        return best
    }

    /// The same address for the same space (whatever its id).
    func isSame(as other: AddressRule) -> Bool {
        kind == other.kind && pattern == other.pattern && spaceID == other.spaceID
    }

    /// `rules` with `rule` added; one already there for the same address
    /// takes its space instead (no duplicate).
    static func adding(_ rule: AddressRule, to rules: [AddressRule]) -> [AddressRule] {
        var rules = rules
        if let index = rules.firstIndex(where: { $0.kind == rule.kind && $0.pattern == rule.pattern }) {
            rules[index].spaceID = rule.spaceID
        } else {
            rules.append(rule)
        }
        return rules
    }

    /// The domain "Always Open … in This Space" uses: the tab's, with its
    /// subdomains. Nil for an address that isn't a web page.
    static func quickRule(for url: URL, spaceID: UUID) -> AddressRule? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, let pattern = normalized(host)
        else { return nil }
        return AddressRule(
            kind: isIPAddress(pattern) ? .domain : .domainAndSubdomains,
            pattern: pattern,
            spaceID: spaceID
        )
    }
}

/// What a link should do with the rules: stay where it is, or go to a space.
enum AddressRouting: Equatable {
    case stay
    case space(UUID)

    /// For a link to `url` that would open in `currentSpaceID`: the rule's
    /// space when it's another one. Never in a private window.
    static func decide(
        url: URL?, currentSpaceID: UUID?, isPrivate: Bool, rules: [AddressRule], spaceIDs: Set<UUID>
    ) -> AddressRouting {
        guard !isPrivate, let url, let rule = AddressRule.rule(for: url, in: rules, spaceIDs: spaceIDs),
              rule.spaceID != currentSpaceID
        else { return .stay }
        return .space(rule.spaceID)
    }
}
