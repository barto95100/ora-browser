import Foundation

/// The user's choices about translation, kept in the app's preferences: the
/// language pages are translated into, the languages always translated, and
/// the sites never offered. Private windows read them but never change the
/// sites (nothing of their browsing is kept).
struct PageTranslationSettings {
    let defaults: UserDefaults

    static var standard: PageTranslationSettings {
        PageTranslationSettings(defaults: .standard)
    }

    private enum Key {
        static let target = "translation.targetLanguage"
        static let alwaysTranslated = "translation.alwaysTranslatedLanguages"
        static let neverOffered = "translation.neverTranslatedSites"
    }

    /// What pages are translated into: the user's choice, else the Mac's language.
    var targetLanguage: Locale.Language {
        guard let identifier = defaults.string(forKey: Key.target), !identifier.isEmpty else {
            return PageLanguage.userLanguage
        }
        return Locale.Language(identifier: identifier)
    }

    func setTargetLanguage(_ language: Locale.Language) {
        defaults.set(language.minimalIdentifier, forKey: Key.target)
    }

    func alwaysTranslates(_ language: Locale.Language) -> Bool {
        guard let code = language.languageCode?.identifier else { return false }
        return strings(Key.alwaysTranslated).contains(code)
    }

    func setAlwaysTranslates(_ language: Locale.Language, _ always: Bool) {
        guard let code = language.languageCode?.identifier else { return }
        update(Key.alwaysTranslated, code, always)
    }

    func neverTranslates(host: String?) -> Bool {
        guard let site = Self.site(host) else { return false }
        return strings(Key.neverOffered).contains(site)
    }

    func setNeverTranslates(host: String?, _ never: Bool) {
        guard let site = Self.site(host) else { return }
        update(Key.neverOffered, site, never)
    }

    /// A site, the same with or without "www.".
    static func site(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private func strings(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    private func update(_ key: String, _ value: String, _ included: Bool) {
        var values = strings(key).filter { $0 != value }
        if included { values.append(value) }
        defaults.set(values, forKey: key)
    }
}
