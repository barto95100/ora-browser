import Foundation

/// An installed extension, as Ombre keeps it between launches. WebKit doesn't
/// remember what was granted: Ombre does, and grants it again at each load.
struct ExtensionRecord: Codable, Equatable, Identifiable {
    enum Source: Codable, Equatable {
        /// A Safari extension inside an app (from the App Store): the `.appex`.
        case safariApp(appexPath: String, bundleIdentifier: String)
        /// From the Chrome Web Store: its id there, and its package in Ombre
        /// (a `.zip`, see `ExtensionPackages`).
        case chromeWebStore(storeID: String, packagePath: String)
        /// A folder or archive the user chose, copied into Ombre.
        case file(packagePath: String)
    }

    /// Also the extension's identity in WebKit (`uniqueIdentifier`), which
    /// keeps its storage between launches.
    let id: String
    var source: Source
    var name: String
    /// The app that brings it, for a Safari extension.
    var appName: String?
    /// The developer team that signs a Safari extension: it must stay the
    /// same (see `SafariExtensionIdentity`).
    var signingTeam: String?
    var isEnabled: Bool
    /// What the user allowed, as WebKit names them (`tabs`, `storage`…).
    var grantedPermissions: [String]
    /// Optional permissions refused when it asked while running: not asked
    /// again (it could ask in a loop).
    var deniedPermissions: [String]
    /// The websites it asked for (`*://*/*`…), granted while `otherSites`
    /// is `.allow`.
    var grantedMatchPatterns: [String]
    /// Websites allowed later, when it asked for them while running.
    var extraMatchPatterns: [String]
    /// Websites without a rule of their own, like Safari's "Other Websites".
    var otherSites: SiteDecision
    /// Allowed or refused websites, by host.
    var siteRules: [SiteRule]
    /// Its button shows next to the sidebar button; unpinned, it is in the
    /// extensions menu.
    var isPinned: Bool
    /// Runs in private windows too (off by default, like Safari).
    var allowsPrivateBrowsing: Bool
    /// Its version, as last loaded (to look for updates).
    var version: String?
    var installedAt: Date

    init(id: String = UUID().uuidString, source: Source, name: String, appName: String?) {
        self.id = id
        self.source = source
        self.name = name
        self.appName = appName
        isEnabled = true
        grantedPermissions = []
        deniedPermissions = []
        grantedMatchPatterns = []
        extraMatchPatterns = []
        otherSites = .ask
        siteRules = []
        isPinned = true
        allowsPrivateBrowsing = false
        installedAt = Date()
    }

    /// Records from before website access: they had all their websites.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(Source.self, forKey: .source)
        name = try container.decode(String.self, forKey: .name)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        signingTeam = try container.decodeIfPresent(String.self, forKey: .signingTeam)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        grantedPermissions = try container.decode([String].self, forKey: .grantedPermissions)
        deniedPermissions = try container.decodeIfPresent([String].self, forKey: .deniedPermissions) ?? []
        grantedMatchPatterns = try container.decode([String].self, forKey: .grantedMatchPatterns)
        extraMatchPatterns = try container.decodeIfPresent([String].self, forKey: .extraMatchPatterns) ?? []
        otherSites = try container.decodeIfPresent(SiteDecision.self, forKey: .otherSites) ?? .allow
        siteRules = try container.decodeIfPresent([SiteRule].self, forKey: .siteRules) ?? []
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        allowsPrivateBrowsing = try container.decodeIfPresent(Bool.self, forKey: .allowsPrivateBrowsing) ?? false
        version = try container.decodeIfPresent(String.self, forKey: .version)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
    }

    /// Allows `names`: no longer refused.
    mutating func grant(_ names: some Sequence<String>) {
        let names = Set(names)
        grantedPermissions = Array(Set(grantedPermissions).union(names)).sorted()
        deniedPermissions.removeAll { names.contains($0) }
    }

    /// Refuses `names` from now on.
    mutating func deny(_ names: some Sequence<String>) {
        let names = Set(names).subtracting(grantedPermissions)
        deniedPermissions = Array(Set(deniedPermissions).union(names)).sorted()
    }

    /// Forgets a refusal: the extension may ask for `name` again.
    mutating func forgetRefusal(of name: String) {
        deniedPermissions.removeAll { $0 == name }
    }

    /// Of `asked`, what was neither allowed nor refused yet.
    func undecidedPermissions(_ asked: [String]) -> [String] {
        asked.filter { !grantedPermissions.contains($0) && !deniedPermissions.contains($0) }
    }

    /// The app's `.appex`, or the package in Ombre.
    var path: String {
        switch source {
        case let .safariApp(path, _): path
        case let .chromeWebStore(_, path): path
        case let .file(path): path
        }
    }

    /// The Safari extension's bundle id (to tell found ones from installed).
    var bundleIdentifier: String? {
        if case let .safariApp(_, identifier) = source { return identifier }
        return nil
    }

    var storeID: String? {
        if case let .chromeWebStore(identifier, _) = source { return identifier }
        return nil
    }

    /// Where it comes from, under its name.
    var originText: String {
        switch source {
        case .safariApp:
            if let appName { String(localized: "From \(appName)") } else { String(localized: "From an app") }
        case .chromeWebStore: String(localized: "From the Chrome Web Store")
        case .file: String(localized: "From a file")
        }
    }
}

/// Whether an extension may read and change a website's pages.
enum SiteDecision: String, Codable, CaseIterable {
    /// Asks the first time it wants to (like Safari).
    case ask
    case allow
    case deny
}

/// A website's decision for an extension; "for one day" ends at `expiresAt`.
struct SiteRule: Codable, Equatable {
    var host: String
    var decision: SiteDecision
    var expiresAt: Date?

    func isActive(at date: Date) -> Bool {
        expiresAt.map { $0 > date } ?? true
    }
}

/// Website access rules, without WebKit.
enum ExtensionSiteAccess {
    /// The match pattern for one website (all its pages, http and https).
    static func pattern(forHost host: String) -> String {
        "*://\(host)/*"
    }

    /// The website of a page, if it is one (http or https).
    static func host(of url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        return host
    }

    /// The decision for a website: its own rule if still valid, else the
    /// one for other websites.
    static func decision(for host: String, in record: ExtensionRecord, at date: Date = Date()) -> SiteDecision {
        record.siteRules.first { $0.host == host && $0.isActive(at: date) }?.decision ?? record.otherSites
    }

    /// Sets a website's rule, replacing its previous one; `.ask` removes it.
    static func setting(
        _ decision: SiteDecision,
        for host: String,
        until expiresAt: Date? = nil,
        in rules: [SiteRule]
    ) -> [SiteRule] {
        var rules = rules.filter { $0.host != host }
        if decision != .ask {
            rules.append(SiteRule(host: host, decision: decision, expiresAt: expiresAt))
        }
        return rules.sorted { $0.host < $1.host }
    }

    /// Rules that ended ("for one day") are dropped.
    static func activeRules(_ rules: [SiteRule], at date: Date = Date()) -> [SiteRule] {
        rules.filter { $0.isActive(at: date) }
    }

    /// Match patterns to grant: the websites asked for when other websites
    /// are allowed, those allowed while running, and allowed websites.
    static func grantedPatterns(for record: ExtensionRecord, at date: Date = Date())
        -> [(pattern: String, expiresAt: Date?)]
    {
        var patterns: [(pattern: String, expiresAt: Date?)] = []
        if record.otherSites == .allow {
            patterns += record.grantedMatchPatterns.map { (pattern: $0, expiresAt: nil) }
        }
        patterns += record.extraMatchPatterns.map { (pattern: $0, expiresAt: nil) }
        for rule in activeRules(record.siteRules, at: date) where rule.decision == .allow {
            patterns.append((pattern: pattern(forHost: rule.host), expiresAt: rule.expiresAt))
        }
        return patterns
    }

    /// Match patterns to refuse: refused websites.
    static func deniedPatterns(for record: ExtensionRecord, at date: Date = Date()) -> [String] {
        activeRules(record.siteRules, at: date).filter { $0.decision == .deny }.map { pattern(forHost: $0.host) }
    }

    /// Patterns meaning every website.
    static let allSitesPatterns: Set<String> = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]
}

/// A Safari extension found in an app, not installed in Ombre yet.
struct SafariExtensionCandidate: Equatable, Identifiable, Sendable {
    let appexURL: URL
    let bundleIdentifier: String
    let name: String
    let appName: String
    let appURL: URL

    var id: String {
        bundleIdentifier
    }
}

/// How the extension permissions read in the review sheet.
enum ExtensionPermissionText {
    static func describe(_ permission: String) -> String {
        descriptions[permission] ?? permission
    }

    /// Sites asked for, in words: all websites, or the list.
    static func describeSites(_ patterns: [String]) -> [String] {
        let allSites: Set = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]
        if patterns.contains(where: allSites.contains) { return [String(localized: "All websites")] }
        return patterns.sorted()
    }

    private static let descriptions: [String: String] = [
        "activeTab": String(localized: "The tab you use it on"),
        "alarms": String(localized: "Run tasks on a schedule"),
        "clipboardRead": String(localized: "Read the clipboard"),
        "clipboardWrite": String(localized: "Write to the clipboard"),
        "contextMenus": String(localized: "Add items to context menus"),
        "cookies": String(localized: "Read and change cookies"),
        "declarativeNetRequest": String(localized: "Block or change web requests"),
        "declarativeNetRequestFeedback": String(localized: "See blocked requests"),
        "declarativeNetRequestWithHostAccess": String(localized: "Block or change web requests on allowed sites"),
        "idle": String(localized: "Know when you're away"),
        "menus": String(localized: "Add items to context menus"),
        "nativeMessaging": String(localized: "Talk to its app"),
        "notifications": String(localized: "Show notifications"),
        "scripting": String(localized: "Run scripts in pages"),
        "storage": String(localized: "Store data"),
        "tabs": String(localized: "See your tabs' addresses and titles"),
        "unlimitedStorage": String(localized: "Store unlimited data"),
        "webNavigation": String(localized: "Follow navigation in tabs"),
        "webRequest": String(localized: "See web requests")
    ]
}
