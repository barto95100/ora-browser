import Foundation

/// Reads what Safari exports (File › Export Browsing Data: a .zip, or the
/// folder it unpacks to): the bookmarks, shared by every profile, and each
/// profile's history. Read in memory, never copied. The files are recognised
/// by what they hold, since their names follow the Mac's language
/// ("Bookmarks.html", "Signets.html"…). Passwords and extensions are left out.
enum SafariImporter {
    enum Failure: Error, Equatable {
        case nothingToImport
        case unreadable
    }

    /// The history of one Safari profile; `name` is nil for the default one.
    struct Profile: Equatable, Sendable {
        var name: String?
        var history: [ImportedVisit]
    }

    struct Export: Equatable, Sendable {
        var profiles: [Profile]
        /// The Favorites bar (Safari's first folder) and the other bookmarks.
        var favoritesBar: [ImportedPinnedItem]
        var otherBookmarks: [ImportedPinnedItem]

        var bookmarkCount: Int {
            ImportedPinnedItem.tabCount(in: favoritesBar) + ImportedPinnedItem.tabCount(in: otherBookmarks)
        }

        /// One space per profile chosen (`profiles` positions); the bookmarks go
        /// to the space at `bookmarksIn`: the Favorites bar as pinned tabs, the
        /// other folders as pinned folders.
        func spaces(profiles chosen: [Int], bookmarksIn: Int?, defaultName: String) -> ImportedBrowserData {
            let spaces = chosen.sorted().filter(profiles.indices.contains).map { index in
                var space = ImportedSpace(name: profiles[index].name ?? defaultName)
                space.history = profiles[index].history
                if index == bookmarksIn {
                    space.pinned = favoritesBar + otherBookmarks
                }
                return space
            }
            return ImportedBrowserData(spaces: spaces)
        }
    }

    /// Visits kept per profile: the most recent ones.
    static let maxVisitsPerProfile = 20000

    static func read(archive: Data) throws -> Export {
        let entries: [ZipReader.Entry]
        do {
            entries = try ZipReader.entries(of: archive, shouldRead: isReadable)
        } catch {
            throw Failure.unreadable
        }
        return try read(files: entries.map { ($0.path, $0.data) })
    }

    /// Only the bookmarks (.html) and histories (.json) are ever read: never
    /// the passwords' file, nor anything else.
    static func isReadable(_ path: String) -> Bool {
        let name = path.lowercased()
        return name.hasSuffix(".html") || name.hasSuffix(".json")
    }

    static let maxFileSize = 32 * 1024 * 1024

    /// The files of an unpacked export folder (not its sub-folders).
    static func read(folder: URL) throws -> Export {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let files = urls.compactMap { url -> (String, Data)? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard isReadable(url.lastPathComponent), values?.isRegularFile == true,
                  (values?.fileSize ?? .max) <= maxFileSize,
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return (url.lastPathComponent, data)
        }
        return try read(files: files)
    }

    static func read(files: [(path: String, data: Data)]) throws -> Export {
        var export = Export(profiles: [], favoritesBar: [], otherBookmarks: [])
        for (path, data) in files {
            let name = (path as NSString).lastPathComponent
            if name.lowercased().hasSuffix(".html"), let html = String(data: data, encoding: .utf8),
               html.trimmingCharacters(in: .whitespacesAndNewlines.union(["\u{FEFF}"]))
                   .lowercased().hasPrefix("<!doctype netscape-bookmark-file-1>")
            {
                let top = SafariBookmarks.parse(html)
                // Safari writes the Favorites bar first, as a folder.
                if case let .folder(_, _, items)? = top.first {
                    export.favoritesBar = items
                    export.otherBookmarks = Array(top.dropFirst())
                } else {
                    export.otherBookmarks = top
                }
            } else if name.lowercased().hasSuffix(".json"), let history = history(from: data) {
                export.profiles.append(Profile(name: profileName(fromFile: name), history: history))
            }
        }
        // The default profile first, then the others by name.
        export.profiles.sort { first, second in
            if (first.name == nil) != (second.name == nil) { return first.name == nil }
            return (first.name ?? "").localizedStandardCompare(second.name ?? "") == .orderedAscending
        }
        guard !export.profiles.isEmpty || export.bookmarkCount > 0 else { throw Failure.nothingToImport }
        // Bookmarks without any history: they still need a space.
        if export.profiles.isEmpty { export.profiles = [Profile(name: nil, history: [])] }
        return export
    }

    /// "History - Work.json" → "Work"; "History.json" (the default profile) → nil.
    static func profileName(fromFile name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        guard let range = base.range(of: " - ") else { return nil }
        // A zip made on macOS may keep names decomposed ("é" as "e" + accent).
        let profile = base[range.upperBound...].trimmingCharacters(in: .whitespaces)
            .precomposedStringWithCanonicalMapping
        return profile.isEmpty ? nil : profile
    }

    /// A history file: `{"metadata": {"data_type": "history"…}, "history": [...]}`.
    static func history(from data: Data) -> [ImportedVisit]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any],
              (metadata["data_type"] as? String)?.lowercased() == "history",
              let items = root["history"] as? [[String: Any]]
        else { return nil }
        let visits = items.compactMap { item -> ImportedVisit? in
            guard let address = item["url"] as? String, let url = URL(string: address),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let microseconds = (item["time_usec"] as? NSNumber)?.int64Value
            else { return nil }
            let title = (item["title"] as? String) ?? ""
            return ImportedVisit(
                url: url,
                title: title.isEmpty ? (url.host ?? address) : title,
                lastVisit: Date(timeIntervalSince1970: TimeInterval(microseconds) / 1_000_000),
                visitCount: max(1, (item["visit_count"] as? NSNumber)?.intValue ?? 1)
            )
        }
        // One entry per address, like Ombre's history: the latest visit, all the visits counted.
        var byAddress: [String: ImportedVisit] = [:]
        for visit in visits {
            let key = visit.url.absoluteString
            guard var known = byAddress[key] else {
                byAddress[key] = visit
                continue
            }
            known.visitCount += visit.visitCount
            if visit.lastVisit > known.lastVisit {
                known.lastVisit = visit.lastVisit
                known.title = visit.title
            }
            byAddress[key] = known
        }
        return Array(byAddress.values.sorted { $0.lastVisit > $1.lastVisit }.prefix(maxVisitsPerProfile))
    }
}

/// Safari's bookmarks file (the Netscape format): `<DT><H3>Folder</H3><DL>…</DL>`
/// and `<DT><A HREF="…">Title</A>`. Web addresses only.
enum SafariBookmarks {
    static func parse(_ html: String) -> [ImportedPinnedItem] {
        let pattern = #"<H3[^>]*>(.*?)</H3>|<A\s[^>]*HREF="([^"]*)"[^>]*>(.*?)</A>|<DL>|</DL>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        else { return [] }
        // A stack of folders being filled; the bottom one is the top level.
        var stack: [(name: String, items: [ImportedPinnedItem])] = [("", [])]
        var pendingFolder: String?
        let text = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let token = text.substring(with: match.range)
            if match.range(at: 1).location != NSNotFound {
                pendingFolder = decode(text.substring(with: match.range(at: 1)))
            } else if match.range(at: 2).location != NSNotFound {
                let address = decode(text.substring(with: match.range(at: 2)))
                guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https"
                else { continue }
                let title = decode(text.substring(with: match.range(at: 3)))
                stack[stack.count - 1].items.append(.tab(ImportedTab(
                    url: url, title: title.isEmpty ? (url.host ?? address) : title
                )))
            } else if token.uppercased() == "<DL>" {
                // The top level's own list has no folder title before it.
                guard let name = pendingFolder else { continue }
                stack.append((name, []))
                pendingFolder = nil
            } else if stack.count > 1 {
                let folder = stack.removeLast()
                stack[stack.count - 1].items.append(.folder(name: folder.name, isOpen: false, items: folder.items))
            }
        }
        // Folders left open by a cut file still count.
        while stack.count > 1 {
            let folder = stack.removeLast()
            stack[stack.count - 1].items.append(.folder(name: folder.name, isOpen: false, items: folder.items))
        }
        return stack[0].items
    }

    static func decode(_ text: String) -> String {
        var result = text
        // Numeric entities (&#233; &#x2019;), then the named ones.
        if let numeric = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let source = result as NSString
            var decoded = ""
            var last = 0
            for match in numeric.matches(in: result, range: NSRange(location: 0, length: source.length)) {
                decoded += source.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = match.range(at: 1).length > 0
                let digits = source.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    decoded += String(Character(scalar))
                } else {
                    decoded += source.substring(with: match.range)
                }
                last = match.range.location + match.range.length
            }
            result = decoded + source.substring(from: last)
        }
        for (entity, character) in [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&amp;", "&")
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
