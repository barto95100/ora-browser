import Combine
import Foundation

/// Site permissions, scoped per space and per origin.
///
/// Spaces have isolated website data, so permissions follow the same
/// boundary: allowing the camera for a site in one space does not allow it in
/// another. Regular spaces are persisted in user defaults; private browsing
/// keeps its choices in memory only, so they are forgotten when the app quits.
///
/// Like `SettingsStore`, this type is meant to be used from the main thread.
final class SitePermissionStore: ObservableObject {
    static let shared = SitePermissionStore()

    typealias SpacePermissions = [SiteOrigin: SitePermissions]

    /// Persisted permissions of regular spaces, keyed by space identifier.
    @Published private(set) var permissionsBySpace: [UUID: SpacePermissions]

    private var privatePermissionsBySpace: [UUID: SpacePermissions] = [:]
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "settings.permissions.sites.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.permissionsBySpace = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Reading

    func permissions(for origin: SiteOrigin, in spaceId: UUID, isPrivate: Bool) -> SitePermissions {
        let spaces = isPrivate ? privatePermissionsBySpace : permissionsBySpace
        return spaces[spaceId]?[origin] ?? SitePermissions()
    }

    // MARK: - Writing

    func setState(
        _ state: SitePermissionState,
        for types: Set<SitePermissionType>,
        origin: SiteOrigin,
        in spaceId: UUID,
        isPrivate: Bool
    ) {
        var permissions = permissions(for: origin, in: spaceId, isPrivate: isPrivate)
        for type in types {
            permissions[type] = state
        }
        setPermissions(permissions, for: origin, in: spaceId, isPrivate: isPrivate)
    }

    /// Saves the permissions of a site. A site set back to "Ask" stays listed in
    /// the settings, so the user can change it again; only
    /// `removePermissions(for:in:isPrivate:)` forgets it, like in Safari.
    func setPermissions(_ permissions: SitePermissions, for origin: SiteOrigin, in spaceId: UUID, isPrivate: Bool) {
        update(permissions, for: origin, in: spaceId, isPrivate: isPrivate)
    }

    func removePermissions(for origin: SiteOrigin, in spaceId: UUID, isPrivate: Bool) {
        update(nil, for: origin, in: spaceId, isPrivate: isPrivate)
    }

    private func update(_ value: SitePermissions?, for origin: SiteOrigin, in spaceId: UUID, isPrivate: Bool) {
        if isPrivate {
            privatePermissionsBySpace[spaceId, default: [:]][origin] = value
        } else {
            permissionsBySpace[spaceId, default: [:]][origin] = value
            if permissionsBySpace[spaceId]?.isEmpty == true {
                permissionsBySpace[spaceId] = nil
            }
            save()
        }
    }

    /// Forgets everything about a space, e.g. when it is deleted.
    func removeAll(in spaceId: UUID) {
        privatePermissionsBySpace[spaceId] = nil
        guard permissionsBySpace[spaceId] != nil else { return }
        permissionsBySpace[spaceId] = nil
        save()
    }

    // MARK: - Persistence

    /// On-disk shape: `[space UUID string: [origin string: permissions]]`,
    /// using string keys so the JSON stays readable and stable.
    private typealias Stored = [String: [String: SitePermissions]]

    private func save() {
        var stored: Stored = [:]
        for (spaceId, origins) in permissionsBySpace {
            stored[spaceId.uuidString] = Dictionary(
                uniqueKeysWithValues: origins.map { ($0.key.description, $0.value) }
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [UUID: SpacePermissions] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return [:] }

        var result: [UUID: SpacePermissions] = [:]
        for (spaceKey, origins) in stored {
            guard let spaceId = UUID(uuidString: spaceKey) else { continue }
            var spacePermissions: SpacePermissions = [:]
            for (originKey, permissions) in origins {
                if let origin = SiteOrigin(string: originKey) {
                    spacePermissions[origin] = permissions
                }
            }
            if !spacePermissions.isEmpty {
                result[spaceId] = spacePermissions
            }
        }
        return result
    }
}
