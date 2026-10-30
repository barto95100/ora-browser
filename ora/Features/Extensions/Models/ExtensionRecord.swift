import Foundation

/// An installed extension, as Ora keeps it between launches. WebKit doesn't
/// remember what was granted: Ora does, and grants it again at each load.
struct ExtensionRecord: Codable, Equatable, Identifiable {
    enum Source: Codable, Equatable {
        /// A Safari extension inside an app (from the App Store): the `.appex`.
        case safariApp(appexPath: String, bundleIdentifier: String)
    }

    /// Also the extension's identity in WebKit (`uniqueIdentifier`), which
    /// keeps its storage between launches.
    let id: String
    var source: Source
    var name: String
    /// The app that brings it, for a Safari extension.
    var appName: String?
    var isEnabled: Bool
    /// What the user allowed, as WebKit names them (`tabs`, `storage`…).
    var grantedPermissions: [String]
    /// Sites the user allowed, as match patterns (`*://*/*`…).
    var grantedMatchPatterns: [String]
    var installedAt: Date

    init(id: String = UUID().uuidString, source: Source, name: String, appName: String?) {
        self.id = id
        self.source = source
        self.name = name
        self.appName = appName
        isEnabled = true
        grantedPermissions = []
        grantedMatchPatterns = []
        installedAt = Date()
    }

    var appexPath: String {
        switch source {
        case let .safariApp(path, _): path
        }
    }
}

/// A Safari extension found in an app, not installed in Ora yet.
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
        if patterns.contains(where: allSites.contains) { return ["All websites"] }
        return patterns.sorted()
    }

    private static let descriptions: [String: String] = [
        "activeTab": "The tab you use it on",
        "alarms": "Run tasks on a schedule",
        "clipboardRead": "Read the clipboard",
        "clipboardWrite": "Write to the clipboard",
        "contextMenus": "Add items to context menus",
        "cookies": "Read and change cookies",
        "declarativeNetRequest": "Block or change web requests",
        "declarativeNetRequestFeedback": "See blocked requests",
        "declarativeNetRequestWithHostAccess": "Block or change web requests on allowed sites",
        "idle": "Know when you're away",
        "menus": "Add items to context menus",
        "nativeMessaging": "Talk to its app",
        "notifications": "Show notifications",
        "scripting": "Run scripts in pages",
        "storage": "Store data",
        "tabs": "See your tabs' addresses and titles",
        "unlimitedStorage": "Store unlimited data",
        "webNavigation": "Follow navigation in tabs",
        "webRequest": "See web requests"
    ]
}
