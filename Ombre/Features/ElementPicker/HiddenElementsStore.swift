import Combine
import Foundation

/// An element the user hid on a site (see `ElementPickerOverlay`).
struct HiddenElement: Codable, Hashable, Identifiable {
    /// The CSS selector that finds it (see `ElementPickerScript`).
    let selector: String
    /// What it showed as when it was hidden ("div.sidebar"), for the lists.
    let label: String
    let date: Date

    var id: String {
        selector
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
