import Foundation
import JavaScriptCore

/// Whether a registered user script runs in a page: its `matches`,
/// `excludeMatches`, `includeGlobs` and `excludeGlobs`, as in Chrome, and
/// the websites the extension may read (Settings › Extensions).
///
/// Decided in the page, from the first line: the matcher is written with
/// the language only (loops, indexes, `===`), no method a page could have
/// replaced, and its rules are literals in the script itself.
enum ExtensionUserScriptMatcher {
    /// The websites the extension may read: every one, or those granted
    /// (until their date), never those refused.
    struct Access: Equatable {
        var allURLs: Bool
        var granted: [(pattern: String, expiresAt: Date?)]
        var denied: [String]

        static func == (lhs: Access, rhs: Access) -> Bool {
            lhs.allURLs == rhs.allURLs && lhs.denied == rhs.denied
                && lhs.granted.map(\.pattern) == rhs.granted.map(\.pattern)
                && lhs.granted.map(\.expiresAt) == rhs.granted.map(\.expiresAt)
        }
    }

    private static let schemes: Set = ["*", "http", "https", "file", "ftp", "ws", "wss"]

    /// A Chrome match pattern: `<all_urls>`, or `scheme://host/path`, the
    /// host `*`, `*.example.com` or without `*`.
    static func isValidPattern(_ pattern: String) -> Bool {
        if pattern == "<all_urls>" { return true }
        guard let range = pattern.range(of: "://") else { return false }
        let scheme = String(pattern[..<range.lowerBound])
        let rest = pattern[range.upperBound...]
        guard schemes.contains(scheme), let slash = rest.firstIndex(of: "/") else { return false }
        let host = rest[..<slash]
        if scheme == "file" { return true }
        guard !host.isEmpty else { return false }
        if host == "*" { return true }
        let name = host.hasPrefix("*.") ? host.dropFirst(2) : host[...]
        return !name.isEmpty && !name.contains("*")
    }

    /// Its scheme and host in lower case, as Chrome compares them.
    static func normalized(_ pattern: String) -> String {
        guard let range = pattern.range(of: "://") else { return pattern }
        let rest = pattern[range.upperBound...]
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        return pattern[..<range.upperBound].lowercased() + rest[..<slash].lowercased() + rest[slash...]
    }

    /// Whether the script runs in a page of `url`, decided by Ombre before
    /// the page loads: the same function as in the pages, in a context of
    /// Ombre's own.
    @MainActor
    static func runs(_ script: ExtensionUserScripts.Script, access: Access, on url: URL, now: Date = Date()) -> Bool {
        guard let check = compiled,
              let result = check.call(withArguments: [rules(for: script, access: access, now: now), url.absoluteString])
        else { return false }
        return result.isBoolean && result.toBool()
    }

    @MainActor private static let compiled: JSValue? = JSContext().flatMap { $0.evaluateScript("(\(function))") }

    private static func rules(for script: ExtensionUserScripts.Script, access: Access, now: Date) -> [String: Any] {
        [
            "m": script.matches.map(normalized),
            "xm": script.excludeMatches.map(normalized),
            "ig": script.includeGlobs,
            "xg": script.excludeGlobs,
            "all": access.allURLs,
            "g": access.granted.filter { $0.expiresAt.map { $0 > now } ?? true }.map { normalized($0.pattern) },
            "d": access.denied.map(normalized)
        ]
    }

    /// The condition a script's code runs under, a JavaScript expression.
    /// Websites allowed until a date: only those still allowed `now` (the
    /// page's clock is the page's; Ombre plans again when one ends).
    static func condition(for script: ExtensionUserScripts.Script, access: Access, now: Date = Date()) -> String {
        let rules = rules(for: script, access: access, now: now)
        // A JSON value is a JavaScript literal: read by the language, not by `JSON.parse`.
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("{}".utf8)
        let literal = String(bytes: data, encoding: .utf8) ?? "{}"
        return "(\(function))(\(literal), location.href)" // not shown
    }

    /// `(rules, href) => Boolean`.
    static let function = #"""
    function (r, href) {
      function cut(s, a, b) { var o = ""; for (var i = a; i < b; i++) o += s[i]; return o; }
      function find(s, c, a) { for (var i = a; i < s.length; i++) if (s[i] === c) return i; return -1; }
      function glob(p, s, q) {
        var pi = 0, si = 0, star = -1, mark = 0;
        while (si < s.length) {
          if (pi < p.length && ((q && p[pi] === "?") || (p[pi] !== "*" && p[pi] === s[si]))) { pi++; si++; }
          else if (pi < p.length && p[pi] === "*") { star = pi; pi++; mark = si; }
          else if (star !== -1) { pi = star + 1; mark++; si = mark; }
          else return false;
        }
        while (pi < p.length && p[pi] === "*") pi++;
        return pi === p.length;
      }
      function parse(h) {
        var colon = find(h, ":", 0);
        if (colon < 1 || h[colon + 1] !== "/" || h[colon + 2] !== "/") return null;
        var start = colon + 3, end = h.length;
        for (var i = start; i < h.length; i++) if (h[i] === "/" || h[i] === "?" || h[i] === "#") { end = i; break; }
        var authority = cut(h, start, end), at = -1;
        for (var j = 0; j < authority.length; j++) if (authority[j] === "@") at = j;
        var host = cut(authority, at + 1, authority.length), hash = find(h, "#", end);
        var path = cut(h, end, hash === -1 ? h.length : hash);
        if (path === "" || path[0] !== "/") path = "/" + path;
        return { scheme: cut(h, 0, colon), host: host, path: path };
      }
      function hostOnly(host) {
        if (host[0] === "[") { var close = find(host, "]", 0); return close === -1 ? host : cut(host, 0, close + 1); }
        var colon = find(host, ":", 0);
        return colon === -1 ? host : cut(host, 0, colon);
      }
      function matches(p, u) {
        var web = u.scheme === "http" || u.scheme === "https";
        if (p === "<all_urls>") {
          return web || u.scheme === "file" || u.scheme === "ftp" || u.scheme === "ws" || u.scheme === "wss";
        }
        var sep = find(p, ":", 0);
        if (sep === -1) return false;
        var scheme = cut(p, 0, sep), slash = find(p, "/", sep + 3);
        if (slash === -1) return false;
        if (scheme === "*" ? !web : scheme !== u.scheme) return false;
        var host = cut(p, sep + 3, slash), path = cut(p, slash, p.length);
        var name = find(host, ":", 0) === -1 && host[0] !== "[" ? hostOnly(u.host) : u.host;
        if (host !== "*") {
          if (host[0] === "*" && host[1] === ".") {
            var base = cut(host, 2, host.length), dot = name.length - base.length - 1;
            var sub = dot > 0 && name[dot] === "." && cut(name, dot + 1, name.length) === base;
            if (name !== base && !sub) return false;
          } else if (host !== name) return false;
        }
        return glob(path, u.path, false);
      }
      function any(list, u) {
        for (var i = 0; i < list.length; i++) if (matches(list[i], u)) return true;
        return false;
      }
      function anyGlob(list) {
        for (var i = 0; i < list.length; i++) if (glob(list[i], href, true)) return true;
        return false;
      }
      var u = typeof href === "string" ? parse(href) : null;
      if (!u) return false;
      if (any(r.d, u)) return false;
      if (!r.all) {
        var allowed = false;
        for (var k = 0; k < r.g.length; k++) if (matches(r.g[k], u)) { allowed = true; break; }
        if (!allowed) return false;
      }
      if (!any(r.m, u) || any(r.xm, u)) return false;
      if (r.ig.length && !anyGlob(r.ig)) return false;
      return !anyGlob(r.xg);
    }
    """#
}
