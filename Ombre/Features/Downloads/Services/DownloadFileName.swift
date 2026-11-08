import Foundation

/// The name a download is saved under, from the one the site suggests:
/// always a plain file of the Downloads folder (WebKit usually cleans the
/// name already, nothing guarantees it).
enum DownloadFileName {
    static let fallback = "download"
    /// Bytes a file name may take on macOS's disks.
    private static let maxBytes = 255

    static func safe(_ suggested: String) -> String {
        // No folder: "/" (and ":", shown as "/" by the Finder) can't name one.
        var name = String(suggested.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == ":" { return "-" }
            if CharacterSet.controlCharacters.contains(scalar) { return " " }
            return Character(scalar)
        })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never a hidden file (".zshrc", ". .zshrc"), nor "." or "..".
        while let first = name.first, first == "." || first.isWhitespace {
            name.removeFirst()
        }
        let short = shortened(name)
        return short.isEmpty || short.hasPrefix(".") ? fallback : short
    }

    /// Cut to the disk's limit, keeping the extension.
    private static func shortened(_ name: String) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty || ext.utf8.count > 16 ? "" : "." + ext
        var base = suffix.isEmpty ? name : String(name.dropLast(suffix.count))
        while base.utf8.count + suffix.utf8.count > maxBytes {
            base.removeLast()
        }
        return base + suffix
    }
}
