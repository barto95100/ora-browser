import Foundation
@preconcurrency import WebKit

/// `chrome.userScripts`: the scripts an extension registers (a user script
/// manager: Tampermonkey, ScriptCat…), kept between launches as in Chrome,
/// and run in the pages it may read (`ExtensionUserScriptInjector`).
///
/// Checked as Chrome does: an error the extension sees for a script
/// without id, a duplicate, a missing `matches`, an invalid pattern…
@MainActor
final class ExtensionUserScripts {
    /// One source of a script: its code, and the file it came from (the
    /// script reads the file of its package and sends its code).
    struct Source: Codable, Equatable {
        var code: String
        var file: String?
    }

    struct Script: Codable, Equatable {
        var id: String
        var matches: [String]
        var excludeMatches: [String]
        var includeGlobs: [String]
        var excludeGlobs: [String]
        var sources: [Source]
        var runAt: String
        var allFrames: Bool
        var world: String
        var worldId: String?

        /// What `getScripts` gives: the file, else the code.
        var dictionary: [String: Any] {
            var value: [String: Any] = [
                "id": id,
                "matches": matches,
                "js": sources.map { source -> [String: Any] in
                    if let file = source.file { return ["file": file] }
                    return ["code": source.code]
                },
                "runAt": runAt,
                "allFrames": allFrames,
                "world": world
            ]
            if !excludeMatches.isEmpty { value["excludeMatches"] = excludeMatches }
            if !includeGlobs.isEmpty { value["includeGlobs"] = includeGlobs }
            if !excludeGlobs.isEmpty { value["excludeGlobs"] = excludeGlobs }
            if let worldId { value["worldId"] = worldId }
            return value
        }
    }

    /// `configureWorld`: whether its scripts may message the extension.
    /// `csp` is kept and given back, but WebKit applies none to a world.
    struct World: Codable, Equatable {
        var worldId: String?
        var csp: String?
        var messaging: Bool

        var dictionary: [String: Any] {
            var value: [String: Any] = ["messaging": messaging]
            if let worldId { value["worldId"] = worldId }
            if let csp { value["csp"] = csp }
            return value
        }
    }

    struct Registered: Codable, Equatable {
        var scripts: [Script] = []
        var worlds: [World] = []

        /// The world's setting, else the default world's, as in Chrome.
        func world(_ worldId: String?) -> World {
            worlds.first { $0.worldId == worldId } ?? worlds.first { $0.worldId == nil }
                ?? World(worldId: worldId, csp: nil, messaging: false)
        }
    }

    static let runTimes: Set = ["document_start", "document_end", "document_idle"]
    static let mainWorld = "MAIN"
    static let userScriptWorld = "USER_SCRIPT"

    private let folder: URL
    private var cache: [String: Registered] = [:]
    /// An extension's scripts changed: the pages get them from their next load.
    var didChange: (String) -> Void = { _ in }

    init(folder: URL = OmbreDataFolder.applicationSupport.appendingPathComponent(
        "Extensions/UserScripts", isDirectory: true // not shown
    )) {
        self.folder = folder
    }

    /// Never a path: the extensions' ids are UUIDs.
    private func fileURL(for id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return folder.appendingPathComponent("\(id.uppercased()).json")
    }

    func registered(for id: String) -> Registered {
        if let cached = cache[id] { return cached }
        let value = fileURL(for: id)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Registered.self, from: $0) } ?? Registered()
        cache[id] = value
        return value
    }

    private func save(_ value: Registered, for id: String) throws {
        guard let url = fileURL(for: id) else { throw Failure.invalid("Invalid extension.") } // not shown
        guard value != registered(for: id) else { return }
        cache[id] = value
        if value == Registered() {
            try? FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        }
        didChange(id)
    }

    /// The extension is removed: its scripts go with it.
    func forget(id: String) {
        guard registered(for: id) != Registered() else { return }
        try? save(Registered(), for: id)
    }

    typealias Failure = ExtensionComplementFailure

    func handle(_ method: String, _ details: [String: Any], extensionID id: String) throws -> Any? {
        var current = registered(for: id)
        switch method {
        case "register":
            let scripts = try Self.list(details["scripts"]).map { try Self.script($0, base: nil) }
            try Self.checkUnique(scripts.map(\.id), existing: current.scripts.map(\.id))
            current.scripts += scripts
            try save(current, for: id)
            return nil
        case "update":
            let changes = try Self.list(details["scripts"])
            var scripts = current.scripts
            var seen = Set<String>()
            for change in changes {
                let scriptID = try Self.scriptID(change)
                guard seen.insert(scriptID).inserted
                else { throw Failure.invalid("Duplicate script ID '\(scriptID)'.") } // not shown
                guard let index = scripts.firstIndex(where: { $0.id == scriptID }) else {
                    throw Failure.invalid("Script with ID '\(scriptID)' does not exist.") // not shown
                }
                scripts[index] = try Self.script(change, base: scripts[index])
            }
            current.scripts = scripts
            try save(current, for: id)
            return nil
        case "unregister":
            let ids = try Self.filterIDs(details["filter"])
            if let ids {
                for scriptID in ids where !current.scripts.contains(where: { $0.id == scriptID }) {
                    throw Failure.invalid("Nonexistent script ID '\(scriptID)'") // not shown
                }
                current.scripts.removeAll { ids.contains($0.id) }
            } else {
                current.scripts = []
            }
            try save(current, for: id)
            return nil
        case "getScripts":
            let ids = try Self.filterIDs(details["filter"])
            return current.scripts.filter { ids?.contains($0.id) ?? true }.map(\.dictionary)
        case "configureWorld", "resetWorldConfiguration", "getWorldConfigurations":
            return try handleWorld(method, details, current: current, extensionID: id)
        default:
            throw Failure.unknownCall("userScripts.\(method)")
        }
    }

    private func handleWorld(
        _ method: String,
        _ details: [String: Any],
        current: Registered,
        extensionID id: String
    ) throws -> Any? {
        var current = current
        switch method {
        case "configureWorld":
            let properties = details["properties"] as? [String: Any] ?? [:]
            let worldId = try Self.worldID(properties["worldId"])
            let world = World(
                worldId: worldId,
                csp: properties["csp"] as? String,
                messaging: properties["messaging"] as? Bool ?? false
            )
            current.worlds.removeAll { $0.worldId == worldId }
            current.worlds.append(world)
            try save(current, for: id)
            return nil
        case "resetWorldConfiguration":
            let worldId = try Self.worldID(details["worldId"])
            current.worlds.removeAll { $0.worldId == worldId }
            try save(current, for: id)
            return nil
        case "getWorldConfigurations":
            return current.worlds.map(\.dictionary)
        default:
            throw Failure.unknownCall("userScripts.\(method)")
        }
    }

    // MARK: Checks, as Chrome's

    private static func list(_ value: Any?) throws -> [[String: Any]] {
        guard let items = value as? [Any] else { throw Failure.invalid("Scripts must be an array.") } // not shown
        return try items.map { item in
            guard let script = item as? [String: Any] else { throw Failure.invalid("Invalid script.") } // not shown
            return script
        }
    }

    private static func scriptID(_ value: [String: Any]) throws -> String {
        guard let id = value["id"] as? String, !id.isEmpty else {
            throw Failure.invalid("Script's ID must not be empty") // not shown
        }
        guard !id.hasPrefix("_")
        else { throw Failure.invalid("Script's ID '\(id)' must not start with '_'") } // not shown
        return id
    }

    private static func checkUnique(_ ids: [String], existing: [String]) throws {
        var seen = Set(existing)
        for id in ids where !seen.insert(id).inserted {
            throw Failure.invalid("Duplicate script ID '\(id)'") // not shown
        }
    }

    private static func filterIDs(_ value: Any?) throws -> Set<String>? {
        guard let filter = value as? [String: Any], let ids = filter["ids"] else { return nil }
        guard let names = ids as? [String] else { throw Failure.invalid("Invalid filter.") } // not shown
        return Set(names)
    }

    private static func worldID(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let id = value as? String, !id.isEmpty, !id.hasPrefix("_") else {
            throw Failure.invalid("Invalid world ID.") // not shown
        }
        return id
    }

    private static func strings(_ value: Any?, _ name: String) throws -> [String]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let items = value as? [String]
        else { throw Failure.invalid("'\(name)' must be an array of strings.") } // not shown
        return items
    }

    private static func patterns(_ value: Any?, _ name: String) throws -> [String]? {
        guard let items = try strings(value, name) else { return nil }
        for item in items where !ExtensionUserScriptMatcher.isValidPattern(item) {
            throw Failure.invalid("Invalid match pattern '\(item)'.") // not shown
        }
        return items
    }

    /// A new script (`base` nil), or `base` with what `value` changes.
    private static func script(_ value: [String: Any], base: Script?) throws -> Script {
        let id = try scriptID(value)
        let matches = try patterns(value["matches"], "matches") ?? base?.matches
        guard let matches, !matches.isEmpty else {
            throw Failure.invalid("Script with ID '\(id)' must specify 'matches'.") // not shown
        }
        let sources = try sources(value["js"], id: id) ?? base?.sources
        guard let sources, !sources.isEmpty else {
            throw Failure.invalid("User script with ID '\(id)' must specify at least one js source.") // not shown
        }
        let runAt = value["runAt"] as? String ?? base?.runAt ?? "document_idle"
        guard runTimes.contains(runAt) else { throw Failure.invalid("Invalid runAt '\(runAt)'.") } // not shown
        let world = value["world"] as? String ?? base?.world ?? userScriptWorld
        guard [mainWorld, userScriptWorld].contains(world) else {
            throw Failure.invalid("Invalid world '\(world)'.") // not shown
        }
        let worldId = value.keys.contains("worldId") ? try worldID(value["worldId"]) : base?.worldId
        if worldId != nil, world == mainWorld {
            throw Failure.invalid("Script with ID '\(id)' can't use a world ID in the main world.") // not shown
        }
        return try Script(
            id: id,
            matches: matches,
            excludeMatches: patterns(value["excludeMatches"], "excludeMatches") ?? base?.excludeMatches ?? [],
            includeGlobs: strings(value["includeGlobs"], "includeGlobs") ?? base?.includeGlobs ?? [],
            excludeGlobs: strings(value["excludeGlobs"], "excludeGlobs") ?? base?.excludeGlobs ?? [],
            sources: sources,
            runAt: runAt,
            allFrames: value["allFrames"] as? Bool ?? base?.allFrames ?? false,
            world: world,
            worldId: world == mainWorld ? nil : worldId
        )
    }

    private static func sources(_ value: Any?, id: String) throws -> [Source]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let items = value as? [[String: Any]] else { throw Failure.invalid("Invalid js sources.") } // not shown
        return try items.map { item in
            let file = item["file"] as? String
            let code = item["code"] as? String
            // A file comes with its code, read by the script from the package.
            guard let code else {
                throw Failure
                    .invalid("User script with ID '\(id)' must specify exactly one of 'code' or 'file'.") // not shown
            }
            if let file, file.isEmpty || file.contains("..") {
                throw Failure.invalid("Invalid file '\(file)'.") // not shown
            }
            return Source(code: code, file: file)
        }
    }
}
