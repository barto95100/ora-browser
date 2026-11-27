import Foundation
import JavaScriptCore
import os.log
@preconcurrency import WebKit

private let logger = Logger(category: "ExtensionComplements")

/// Runs the extensions' user scripts (`chrome.userScripts`) in the pages of
/// the tabs: in every page, from its next load (as Chrome), each script
/// guarded by its rules and the websites its extension may read
/// (`ExtensionUserScriptMatcher`). In private windows only for the
/// extensions allowed there.
@available(macOS 15.4, *)
@MainActor
final class ExtensionUserScriptInjector {
    static let shared = ExtensionUserScriptInjector()

    /// What an extension running now has registered, and where it may run.
    struct Entry {
        let extensionID: String
        let access: ExtensionUserScriptMatcher.Access
        let allowsPrivate: Bool
        let registered: ExtensionUserScripts.Registered
    }

    /// A script to add to the pages.
    struct Planned: Hashable {
        let source: String
        let injectionTime: WKUserScriptInjectionTime
        let forMainFrameOnly: Bool
        /// Nil: the page's world (`MAIN`).
        let worldName: String?
    }

    /// A world whose scripts may message their extension.
    struct MessagingWorld: Equatable {
        let extensionID: String
        let worldId: String?
        let name: String
    }

    /// The extensions running with user scripts (none until the extensions start).
    var entries: () -> [Entry] = { [] }
    /// The channel of a messaging world's scripts.
    var handler: (MessagingWorld) -> WKScriptMessageHandlerWithReply? = { _ in nil }

    private let pages = NSHashTable<BrowserPage>.weakObjects()
    /// The same script, the same object: a page whose scripts didn't change
    /// keeps them (nothing removed and added again). Those of the plans
    /// before are kept too: a manager that unregisters, then registers the
    /// same scripts again, changes nothing in the pages.
    private var made: [Planned: WKUserScript] = [:]
    private var used: Set<Planned> = []
    private var previouslyUsed: Set<Planned> = []
    /// Planning again when a website allowed for a while stops being allowed.
    private var expiryTask: Task<Void, Never>?

    static func worldName(extensionID: String, worldId: String?) -> String {
        "ombre.userScripts.\(extensionID).\(worldId ?? "")" // not shown
    }

    func attach(_ page: BrowserPage) {
        pages.add(page)
        apply(to: page)
    }

    /// An extension's own page (popup, options…): none of the user scripts.
    func detach(_ page: BrowserPage) {
        pages.remove(page)
        install(([], []), in: page)
    }

    /// The page is closed: no more scripts for it.
    func forget(_ page: BrowserPage) {
        pages.remove(page)
    }

    /// Before the page of `url` loads (its main frame): the scripts that
    /// run there, decided by Ombre, and those of every frame.
    func prepare(_ page: BrowserPage, for url: URL?) {
        guard pages.contains(page) else { return }
        page.extensionUserScriptsURL = url
        apply(to: page)
    }

    /// Something changed (scripts, an extension, its websites): every page
    /// gets the new scripts for its next load.
    func refresh() {
        previouslyUsed = used
        used = []
        let entries = entries()
        scheduleExpiry(entries)
        for page in pages.allObjects {
            apply(to: page, entries: entries)
        }
        made = made.filter { used.contains($0.key) || previouslyUsed.contains($0.key) }
    }

    private func apply(to page: BrowserPage, entries: [Entry]? = nil) {
        guard !page.isExtensionPage else { return }
        let plan = Self.plan(entries ?? self.entries(), isPrivate: page.isPrivate, url: page.extensionUserScriptsURL)
        used.formUnion(plan.scripts)
        let scripts = plan.scripts.map { planned in
            if let script = made[planned] { return script }
            let script = WKUserScript(
                source: planned.source,
                injectionTime: planned.injectionTime,
                forMainFrameOnly: planned.forMainFrameOnly,
                in: planned.worldName.map { WKContentWorld.world(name: $0) } ?? .page
            )
            made[planned] = script
            return script
        }
        install((scripts, plan.worlds.map { (WKContentWorld.world(name: $0.name), $0) }), in: page)
    }

    private func install(
        _ current: (scripts: [WKUserScript], worlds: [(WKContentWorld, MessagingWorld)]),
        in page: BrowserPage
    ) {
        guard current.scripts.map(ObjectIdentifier.init) != page.extensionUserScripts.map(ObjectIdentifier.init)
            || current.worlds.map(\.0) != page.extensionUserScriptWorlds
        else { return }
        let controller = page.webView.configuration.userContentController
        for world in page.extensionUserScriptWorlds {
            controller.removeScriptMessageHandler(forName: ExtensionUserScriptMessages.handlerName, contentWorld: world)
        }
        // No API removes one script: all of them, then the others again.
        let previous = Set(page.extensionUserScripts.map(ObjectIdentifier.init))
        let kept = controller.userScripts.filter { !previous.contains(ObjectIdentifier($0)) }
        controller.removeAllUserScripts()
        (kept + current.scripts).forEach(controller.addUserScript)
        for (world, messaging) in current.worlds {
            guard let handler = handler(messaging) else { continue }
            controller.addScriptMessageHandler(
                handler,
                contentWorld: world,
                name: ExtensionUserScriptMessages.handlerName
            )
        }
        page.extensionUserScripts = current.scripts
        page.extensionUserScriptWorlds = current.worlds.map(\.0)
    }

    /// Once, at the next end of a website allowed for a while (no polling).
    private func scheduleExpiry(_ entries: [Entry]) {
        expiryTask?.cancel()
        let now = Date()
        let next = entries.flatMap { $0.access.granted.compactMap(\.expiresAt) }.filter { $0 > now }.min()
        guard let next else { return expiryTask = nil }
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 1))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// The scripts of a page whose main frame shows `url` (nil: not known
    /// yet), in the order registered:
    /// - a script of the main frame only: only if it runs at `url`, as it is;
    /// - a script of every frame (`allFrames`): always, guarded in each frame;
    /// - before them, in a world with messaging used here, its `chrome.runtime`.
    static func plan(
        _ entries: [Entry],
        isPrivate: Bool,
        url: URL?,
        now: Date = Date()
    ) -> (scripts: [Planned], worlds: [MessagingWorld]) {
        var runtimes: [Planned] = []
        var scripts: [Planned] = []
        var worlds: [MessagingWorld] = []
        for entry in entries where !isPrivate || entry.allowsPrivate {
            // By world: whether a script of it is here, and in which frames.
            var here: [String?: (whole: Bool, guards: [String])] = [:]
            for script in entry.registered.scripts {
                let condition = ExtensionUserScriptMatcher.condition(for: script, access: entry.access, now: now)
                let isMain = script.world == ExtensionUserScripts.mainWorld
                if !script.allFrames {
                    guard let url, ExtensionUserScriptMatcher.runs(script, access: entry.access, on: url, now: now)
                    else { continue }
                }
                if !isMain {
                    var world = here[script.worldId] ?? (false, [])
                    if script.allFrames { world.guards.append(condition) } else { world.whole = true }
                    here[script.worldId] = world
                }
                let worldName = isMain ? nil : worldName(extensionID: entry.extensionID, worldId: script.worldId)
                for source in script.sources {
                    // "document_idle" runs at the end of the content, which Chrome
                    // allows ("between document_end and just after load").
                    guard let code = script.allFrames ? guarded(source.code, condition) : source.code else { continue }
                    scripts.append(Planned(
                        source: code,
                        injectionTime: script.runAt == "document_start" ? .atDocumentStart : .atDocumentEnd,
                        forMainFrameOnly: !script.allFrames,
                        worldName: worldName
                    ))
                }
            }
            for (worldId, world) in here.sorted(by: { ($0.key ?? "") < ($1.key ?? "") })
                where entry.registered.world(worldId).messaging
            {
                let messaging = MessagingWorld(
                    extensionID: entry.extensionID,
                    worldId: worldId,
                    name: worldName(extensionID: entry.extensionID, worldId: worldId)
                )
                worlds.append(messaging)
                let runtime = ExtensionUserScriptMessages.runtimeSource(extensionID: entry.extensionID)
                // In the main frame when a script runs there; in the frames
                // only where one of the world's scripts of every frame runs.
                let condition = world.guards.map { "(\($0))" }.joined(separator: " || ")
                let source = world.guards.isEmpty ? runtime
                    : guarded(runtime, (world.whole ? "window === window.top || " : "") + condition) ?? "" // not shown
                runtimes.append(Planned(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: world.guards.isEmpty,
                    worldName: messaging.name
                ))
            }
        }
        return (runtimes + scripts, worlds)
    }

    /// A script of every frame, in a frame where it may not run: its code in
    /// a block run only where it may, only if it is a whole script by itself
    /// (so it can't end the block early). No error where it doesn't run: a
    /// page receives even those of other worlds (`error` events). Its `let`,
    /// `const` and `class` are the block's, and a leading "use strict" no
    /// longer applies: unlike Chrome, for these scripts only.
    static func guarded(_ code: String, _ condition: String) -> String? {
        guard isWholeScript(code) else {
            logger.notice("A user script of every frame isn't a whole script: not run")
            return nil
        }
        return "if (\(condition)) {\n\(code)\n}\n" // not shown
    }

    private static var checkedScripts: [String: Bool] = [:]
    private static let syntaxContext = JSGlobalContextCreate(nil)

    /// Whether `code` parses as a script by itself (not run).
    static func isWholeScript(_ code: String) -> Bool {
        if let known = checkedScripts[code] { return known }
        let source = JSStringCreateWithCFString(code as CFString)
        defer { JSStringRelease(source) }
        let valid = JSCheckScriptSyntax(syntaxContext, source, nil, 1, nil)
        if checkedScripts.count > 500 { checkedScripts = [:] }
        checkedScripts[code] = valid
        return valid
    }
}
