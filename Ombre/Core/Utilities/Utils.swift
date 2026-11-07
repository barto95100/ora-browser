import Foundation

func extractDomainOrIP(from text: String) -> String? {
    guard let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)") else {
        return nil
    }

    guard let host = url.host else {
        return nil
    }

    return host
}

func isValidURL(_ text: String) -> Bool {
    if localFileURL(from: text) != nil { return true }
    guard let host = extractDomainOrIP(from: text) else { return false }

    if host == "localhost" {
        return true
    }

    let ipPattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
    if host.range(of: ipPattern, options: .regularExpression) != nil {
        return true
    }

    let domainPattern =
        #"^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$"#

    return host.range(of: domainPattern, options: .regularExpression) != nil
}

func constructURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let file = localFileURL(from: trimmed) {
        return file
    }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return URL(string: trimmed)
    }
    guard isValidURL(trimmed) else { return nil }
    let host = extractDomainOrIP(from: trimmed)
    let scheme = (host == "localhost") ? "http" : "https"
    return URL(string: "\(scheme)://\(trimmed)")
}

/// A local file typed in the address bar, like Safari: `file:///…` (with its
/// `#fragment` or `?query`), or an existing file's absolute path (`/Users/…`)
/// or path in the home folder (`~/…`). A bare path to nothing (`/r/swift`) is
/// a search.
func localFileURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.range(of: "file://", options: [.caseInsensitive, .anchored]) != nil {
        var rest = String(trimmed.dropFirst("file://".count))
        if rest.range(of: "localhost/", options: [.caseInsensitive, .anchored]) != nil {
            rest = String(rest.dropFirst("localhost".count))
        }
        // The path, then what follows it.
        let end = rest.firstIndex { $0 == "#" || $0 == "?" } ?? rest.endIndex
        let path = String(rest[..<end])
        let decoded = path.removingPercentEncoding ?? path
        guard decoded.hasPrefix("/") else { return nil }
        let file = URL(fileURLWithPath: decoded)
        guard end < rest.endIndex,
              var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
        else { return file }
        let suffix = String(rest[end...])
        if let hash = suffix.firstIndex(of: "#") {
            let query = suffix[..<hash].dropFirst()
            components.percentEncodedQuery = query.isEmpty ? nil : String(query)
            components.percentEncodedFragment = String(suffix[suffix.index(after: hash)...])
        } else {
            components.percentEncodedQuery = String(suffix.dropFirst())
        }
        return components.url ?? file
    }
    let path: String
    if trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") {
        path = trimmed
    } else if trimmed.hasPrefix("~/") {
        path = expandingHomeFolder(trimmed)
    } else {
        return nil
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        return nil
    }
    return URL(fileURLWithPath: path)
}

/// `~/…` in the user's home folder.
func expandingHomeFolder(_ path: String) -> String {
    path.hasPrefix("~/") ? realHomeDirectory + path.dropFirst() : path
}

/// The user's home folder: in the sandbox, `NSHomeDirectory()` is the app's
/// container.
private var realHomeDirectory: String {
    guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return NSHomeDirectory() }
    return String(cString: home)
}
