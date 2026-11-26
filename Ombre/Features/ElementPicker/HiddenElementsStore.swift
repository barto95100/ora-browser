import Combine
import Foundation

/// An element the user hid on a site (see `ElementPickerOverlay`).
struct HiddenElement: Codable, Hashable, Identifiable {
    /// The CSS selector that finds it (see `ElementPickerScript`).
    let selector: String
    /// What it showed as when it was hidden ("div.sidebar"), for the lists.
    let label: String
    let date: Date
    /// Its own words when it was hidden (`aria-label`, title, heading or the
    /// start of its text): it isn't shown afterwards. Nil before they were kept.
    var name: String?
    /// Its kind ("sidebar", "navigation"…), from its role or its tag.
    var kind: String?

    var id: String {
        selector
    }

    init(selector: String, label: String, date: Date, name: String? = nil, kind: String? = nil) {
        self.selector = selector
        self.label = label
        self.date = date
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.kind = kind
    }

    /// The title of the lists: its words, else a name for its kind; elements
    /// hidden before their words were kept: a kind told by their label.
    var title: String {
        if let name { return name }
        if let title = Self.kindTitle(kind ?? Self.kind(fromLabel: label)) { return title }
        return String(localized: "Element")
    }

    /// A kind guessed from words of the label ("div.cs-sidebar__inner": a sidebar).
    static func kind(fromLabel label: String) -> String? {
        let lowered = label.lowercased()
        let tag = String(lowered.prefix { $0.isLetter || $0.isNumber })
        let hints: [(String, String)] = [
            ("sidebar", "sidebar"), ("aside", "sidebar"), ("cookie", "cookies"), ("consent", "cookies"),
            ("banner", "banner"), ("header", "banner"), ("footer", "footer"), ("nav", "navigation"),
            ("menu", "menu"), ("modal", "dialog"), ("popup", "dialog"), ("dialog", "dialog"),
            ("newsletter", "newsletter"), ("advert", "ad"), ("promo", "ad"), ("comment", "comments"),
            ("toolbar", "toolbar"), ("search", "search")
        ]
        if let hint = hints.first(where: { lowered.dropFirst(tag.count).contains($0.0) }) { return hint.1 }
        let tags = [
            "nav": "navigation", "aside": "sidebar", "header": "banner", "footer": "footer", "dialog": "dialog",
            "form": "form", "img": "image", "picture": "image", "figure": "image", "svg": "image",
            "video": "video", "iframe": "embed", "main": "main", "article": "article", "section": "section",
            "ul": "list", "ol": "list", "table": "table", "button": "button"
        ]
        return tags[tag]
    }

    static func kindTitle(_ kind: String?) -> String? {
        guard let kind else { return nil }
        let titles = [
            "navigation": String(localized: "hiddenElement.navigation", defaultValue: "Navigation"),
            "sidebar": String(localized: "Sidebar"),
            "banner": String(localized: "hiddenElement.banner", defaultValue: "Banner"),
            "footer": String(localized: "hiddenElement.footer", defaultValue: "Footer"),
            "dialog": String(localized: "hiddenElement.dialog", defaultValue: "Dialog"),
            "search": String(localized: "hiddenElement.search", defaultValue: "Search Box"),
            "form": String(localized: "hiddenElement.form", defaultValue: "Form"),
            "image": String(localized: "hiddenElement.image", defaultValue: "Image"),
            "video": String(localized: "hiddenElement.video", defaultValue: "Video"),
            "audio": String(localized: "hiddenElement.audio", defaultValue: "Audio Player"),
            "embed": String(localized: "hiddenElement.embed", defaultValue: "Embedded Content"),
            "main": String(localized: "hiddenElement.main", defaultValue: "Main Content"),
            "article": String(localized: "hiddenElement.article", defaultValue: "Article"),
            "section": String(localized: "hiddenElement.section", defaultValue: "Section"),
            "list": String(localized: "hiddenElement.list", defaultValue: "List"),
            "table": String(localized: "hiddenElement.table", defaultValue: "Table"),
            "menu": String(localized: "hiddenElement.menu", defaultValue: "Menu"),
            "toolbar": String(localized: "hiddenElement.toolbar", defaultValue: "Toolbar"),
            "button": String(localized: "hiddenElement.button", defaultValue: "Button"),
            "notice": String(localized: "hiddenElement.notice", defaultValue: "Notice"),
            "cookies": String(localized: "hiddenElement.cookies", defaultValue: "Cookie Banner"),
            "newsletter": String(localized: "hiddenElement.newsletter", defaultValue: "Newsletter Box"),
            "ad": String(localized: "hiddenElement.ad", defaultValue: "Ad"),
            "comments": String(localized: "hiddenElement.comments", defaultValue: "Comments")
        ]
        return titles[kind]
    }
}

/// The elements hidden on each site, per space. Saved in the user defaults
/// for regular spaces; a private window's are never recorded.
///
/// The site is the registrable domain (`WebSite.registrableDomain(of:)`), as
/// for the protections: an element hidden on `www.example.com` stays hidden
/// on `news.example.com`.
@MainActor
final class HiddenElementsStore: ObservableObject {
    static let shared = HiddenElementsStore()

    typealias SpaceElements = [String: [HiddenElement]]

    /// Keyed by space, then by site.
    @Published private(set) var elementsBySpace: [UUID: SpaceElements]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "settings.hiddenElements.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        elementsBySpace = Self.load(from: defaults, key: storageKey)
    }

    func elements(onSite site: String, in spaceID: UUID) -> [HiddenElement] {
        elementsBySpace[spaceID]?[site] ?? []
    }

    func elements(in spaceID: UUID) -> SpaceElements {
        elementsBySpace[spaceID] ?? [:]
    }

    /// Whether it was added (not already there).
    @discardableResult
    func hide(_ element: HiddenElement, onSite site: String, in spaceID: UUID) -> Bool {
        var elements = elements(onSite: site, in: spaceID)
        guard !elements.contains(where: { $0.selector == element.selector }) else { return false }
        elements.append(element)
        set(elements, onSite: site, in: spaceID)
        return true
    }

    func show(_ selector: String, onSite site: String, in spaceID: UUID) {
        set(elements(onSite: site, in: spaceID).filter { $0.selector != selector }, onSite: site, in: spaceID)
    }

    func showAll(onSite site: String, in spaceID: UUID) {
        set([], onSite: site, in: spaceID)
    }

    /// Forgets everything about a space, e.g. when it is deleted.
    /// Whether it had any.
    @discardableResult
    func removeAll(in spaceID: UUID) -> Bool {
        guard elementsBySpace[spaceID] != nil else { return false }
        elementsBySpace[spaceID] = nil
        save()
        return true
    }

    private func set(_ elements: [HiddenElement], onSite site: String, in spaceID: UUID) {
        var space = elementsBySpace[spaceID] ?? [:]
        space[site] = elements.isEmpty ? nil : elements
        elementsBySpace[spaceID] = space.isEmpty ? nil : space
        save()
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: elementsBySpace.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [UUID: SpaceElements] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: SpaceElements].self, from: data)
        else { return [:] }
        var result: [UUID: SpaceElements] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) { result[id] = value }
        }
        return result
    }
}
