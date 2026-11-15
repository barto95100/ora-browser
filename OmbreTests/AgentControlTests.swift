import AppKit
import Foundation
@testable import Ombre
import Testing

/// Sessions: one question per app, until Ombre quits or an hour without a
/// command.
struct AgentSessionsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func aNewAppIsAsked() {
        var sessions = AgentSessions()
        #expect(sessions.decision(for: "com.apple.Terminal", now: start) == .ask)
    }

    @Test func theAnswerHoldsForTheSession() {
        var sessions = AgentSessions()
        sessions.record("term", isAllowed: true, now: start)
        sessions.record("editor", isAllowed: false, now: start)
        #expect(sessions.decision(for: "term", now: start + 60) == .allowed)
        #expect(sessions.decision(for: "editor", now: start + 60) == .denied)
        #expect(sessions.decision(for: "other", now: start + 60) == .ask)
    }

    /// Each command keeps the session alive; an hour without one ends it.
    @Test func anHourWithoutACommandEndsTheSession() {
        var sessions = AgentSessions()
        sessions.record("term", isAllowed: true, now: start)
        #expect(sessions.decision(for: "term", now: start + 3000) == .allowed)
        #expect(sessions.decision(for: "term", now: start + 6000) == .allowed)
        #expect(sessions.decision(for: "term", now: start + 6000 + AgentSessions.idleLimit + 1) == .ask)
    }

    @Test func stoppingEndsEverySession() {
        var sessions = AgentSessions()
        sessions.record("term", isAllowed: true, now: start)
        sessions.endAll()
        #expect(sessions.decision(for: "term", now: start) == .ask)
    }
}

/// Where the agents' indicator shows: the sidebar's header, else the address bar.
struct SidebarHeaderPlacementTests {
    @Test(arguments: [
        (SidebarPosition.primary, false, false, true),
        (.primary, false, true, false),
        (.secondary, false, false, false),
        (.secondary, true, false, true),
        (.primary, true, true, true)
    ])
    func theHeaderShows(_ position: SidebarPosition, toolbarHidden: Bool, fullscreen: Bool, shown: Bool) {
        #expect(SidebarHeader
            .isShown(position: position, isToolbarHidden: toolbarHidden, isFullscreen: fullscreen) == shown)
    }
}

/// The app named is the one the user knows, up the sender's parents.
struct AgentSenderLookupTests {
    @Test func theFirstRegularAppUpTheParents() {
        // osascript (30) ← zsh (20) ← Terminal (10)
        let parents: [pid_t: pid_t] = [30: 20, 20: 10]
        let terminal = AgentSender(key: "com.apple.Terminal", name: "Terminal")
        let sender = AgentSenderLookup.sender(
            pid: 30,
            app: { $0 == 10 ? terminal : nil },
            parent: { parents[$0] }
        )
        #expect(sender == terminal)
    }

    @Test func unknownWhenNoAppIsFound() {
        let sender = AgentSenderLookup.sender(pid: 30, app: { _ in nil }, parent: { $0 - 1 })
        #expect(sender.key == "unknown")
    }

    /// The real lookup reads a process's parent as macOS knows it (none for
    /// launchd), from the sandbox too.
    @Test func theParentOfAProcessIsRead() {
        let parent = getppid()
        #expect(AgentSenderLookup.parent(of: getpid()) == (parent > 1 ? parent : nil))
    }
}

/// The sdef is in the app and maps each event to its command.
@MainActor
struct AgentScriptingDefinitionTests {
    @Test func everyCommandIsDefined() {
        let registry = NSScriptSuiteRegistry.shared()
        let commands: [(code: String, type: AnyClass)] = [
            ("LsTb", ListTabsScriptCommand.self),
            ("OpAd", OpenAddressScriptCommand.self),
            ("AcTb", ActivateTabScriptCommand.self),
            ("ClTb", CloseTabScriptCommand.self),
            ("RdTb", ReadTabScriptCommand.self)
        ]
        for command in commands {
            let description = registry.commandDescription(
                withAppleEventClass: Self.code("Ombr"),
                andAppleEventCode: Self.code(command.code)
            )
            #expect(description?.commandClassName == NSStringFromClass(command.type), "\(command.code)")
        }
    }

    private static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}

extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct AgentControlTests {
        private let terminal = AgentSender(key: "com.apple.Terminal", name: "Terminal")

        /// A control of its own, on `window`, allowed in the settings and
        /// answering `answer`; counts the questions.
        private final class Asked {
            var questions = 0
        }

        private func control(
            _ window: TabManagerTestWindow?,
            allowed: Bool = true,
            answer: Bool? = true,
            asked: Asked = Asked(),
            whileAsking: @escaping @MainActor (AgentControl) -> Void = { _ in }
        ) -> AgentControl {
            let control = AgentControl()
            control.isAllowed = { allowed }
            control.ask = { [unowned control] _ in
                asked.questions += 1
                whileAsking(control)
                return answer
            }
            control.tabManager = { window?.tabManager }
            return control
        }

        @Test func offInTheSettingsNothingIsAsked() async {
            let asked = Asked()
            let control = control(nil, allowed: false, asked: asked)
            #expect(await control.run(.listTabs, from: terminal) == .failure(.off))
            #expect(asked.questions == 0)
            #expect(control.drivingApp == nil)
        }

        @Test func deniedOnceDeniedForTheSession() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, answer: false, asked: asked)
                #expect(await control.run(.listTabs, from: terminal) == .failure(.denied))
                #expect(await control.run(.listTabs, from: terminal) == .failure(.denied))
                #expect(asked.questions == 1)
            }
        }

        /// No answer in time: the command fails, and the app is asked again.
        @Test func noAnswerAsksAgain() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, answer: nil, asked: asked)
                #expect(await control.run(.listTabs, from: terminal) == .failure(.unanswered))
                #expect(await control.run(.listTabs, from: terminal) == .failure(.unanswered))
                #expect(asked.questions == 2)
            }
        }

        /// Stop while the user is asked: their answer isn't kept.
        @Test func stopDuringTheQuestionDropsTheAnswer() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, asked: asked, whileAsking: { $0.stop() })
                #expect(await control.run(.listTabs, from: terminal) == .failure(.unanswered))
                #expect(asked.questions == 1)
                #expect(control.drivingApp == nil)
            }
        }

        /// A sender whose app isn't known is asked about each command.
        @Test func anUnknownAppIsAskedEachTime() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, asked: asked)
                let unknown = AgentSender(key: AgentSender.unknownKey, name: "An app")
                _ = try await control.run(.listTabs, from: unknown).get()
                _ = try await control.run(.listTabs, from: unknown).get()
                #expect(asked.questions == 2)
            }
        }

        /// Commands sent while the user is asked wait for the same answer.
        @Test func oneQuestionForCommandsSentTogether() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, asked: asked)
                async let first = control.run(.listTabs, from: terminal)
                async let second = control.run(.listTabs, from: terminal)
                let results = await [first, second]
                #expect(results.allSatisfy { (try? $0.get()) != nil })
                #expect(asked.questions == 1)
                #expect(control.drivingApp == "Terminal")
            }
        }

        @Test func stoppingAsksAgain() async throws {
            try await TabManagerTestWindow.run { window in
                let asked = Asked()
                let control = control(window, asked: asked)
                _ = await control.run(.listTabs, from: terminal)
                control.stop()
                #expect(control.drivingApp == nil)
                _ = await control.run(.listTabs, from: terminal)
                #expect(asked.questions == 2)
            }
        }

        /// No window, nothing asked.
        @Test func noWindowNoCommand() async {
            let asked = Asked()
            #expect(await control(nil, asked: asked).run(.listTabs, from: terminal) == .failure(.noWindow))
            #expect(asked.questions == 0)
        }

        @Test func listOpenActivateClose() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/a")), title: "Example", in: space,
                    isPrivate: false
                )
                let control = control(window)

                let list = try await control.run(.listTabs, from: terminal).get()
                let spaces = try JSONDecoder().decode([AgentSpace].self, from: Data(list.utf8))
                let listed = try #require(spaces.first { $0.id == space.id.uuidString })
                #expect(listed.tabs.map(\.id).contains(tab.id.uuidString))
                #expect(listed.tabs.first { $0.id == tab.id.uuidString }?.address == "https://example.com/a")

                let shown = try await control.run(.activate(tab.id.uuidString.lowercased()), from: terminal).get()
                #expect(shown.contains(tab.id.uuidString))
                #expect(window.tabManager.activeTab?.id == tab.id)

                // Its id kept: the tab goes away after its close.
                let id = tab.id.uuidString
                _ = try await control.run(.close(id), from: terminal).get()
                #expect(await control.run(.close(id), from: terminal) == .failure(.noTab))
            }
        }

        @Test func anAddressOpensInANewTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                // Its page loads nothing kept on the disk.
                window.tabManager.isPrivateWindow = true
                let control = control(window)
                let reply = try await control.run(.open("http://127.0.0.1:1/agent"), from: terminal).get()
                let opened = try JSONDecoder().decode(AgentTab.self, from: Data(reply.utf8))
                #expect(opened.address == "http://127.0.0.1:1/agent")
                #expect(space.tabs.contains { $0.id.uuidString == opened.id })
            }
        }

        /// The tabs an agent opened, showed or read get a badge; listing or a
        /// failed command doesn't; Stop removes them all.
        @Test func touchedTabsGetABadgeUntilStop() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let shown = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/a")), title: "A", in: space, isPrivate: false
                )
                let untouched = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/b")), title: "B", in: space, isPrivate: false
                )
                window.tabManager.isPrivateWindow = true
                let control = control(window)

                _ = try await control.run(.listTabs, from: terminal).get()
                #expect(control.touchedTabIDs.isEmpty)
                #expect(control.drivingApp == "Terminal")

                _ = try await control.run(.activate(shown.id.uuidString), from: terminal).get()
                let reply = try await control.run(.open("http://127.0.0.1:1/agent"), from: terminal).get()
                let opened = try JSONDecoder().decode(AgentTab.self, from: Data(reply.utf8))
                _ = await control.run(.read(untouched.id.uuidString), from: terminal) // not loaded: fails
                #expect(try control.touchedTabIDs == [shown.id, #require(UUID(uuidString: opened.id))])

                control.stop()
                #expect(control.touchedTabIDs.isEmpty)
                #expect(control.drivingApp == nil)
            }
        }

        /// An hour without a command ends the indicator and the badges.
        @Test func idleEndsTheIndicatorAndBadges() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/a")), title: "A", in: space, isPrivate: false
                )
                let control = control(window)
                control.idleLimit = 0.05
                _ = try await control.run(.activate(tab.id.uuidString), from: terminal).get()
                #expect(control.touchedTabIDs == [tab.id])
                await window.waitUntil("idle end") { control.drivingApp == nil }
                #expect(control.touchedTabIDs.isEmpty)
            }
        }

        /// A private tab is never listed, shown, closed or read.
        @Test func privateTabsAreNeverReached() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/private")), title: "Private", in: space,
                    isPrivate: true
                )
                let control = control(window)
                let list = try await control.run(.listTabs, from: terminal).get()
                #expect(!list.contains(tab.id.uuidString))
                for command in [
                    AgentCommand.activate(tab.id.uuidString),
                    .close(tab.id.uuidString),
                    .read(tab.id.uuidString)
                ] {
                    #expect(await control.run(command, from: terminal) == .failure(.noTab))
                }
                #expect(!tab.isClosing)
            }
        }

        /// Only web addresses: never a script, a file or Ombre's own pages.
        @Test(arguments: ["javascript:alert(1)", "file:///etc/hosts", "ombre://settings", "not an address", "https://"])
        func onlyWebAddressesOpen(address: String) async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                #expect(await control.run(.open(address), from: terminal) == .failure(.badAddress))
            }
        }

        @Test func aTabWithoutItsPageIsNotRead() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/")), title: "Example", in: space,
                    isPrivate: false
                )
                let control = control(window)
                #expect(await control.run(.read(tab.id.uuidString), from: terminal) == .failure(.notLoaded))
                #expect(await control.run(.read("nope"), from: terminal) == .failure(.noTab))
            }
        }
    }
}

/// A real Apple Event goes through the sdef (sent to the test host itself,
/// which needs no permission). `open address` without its address: Cocoa
/// Scripting knows the command and says its parameter is missing (-1701), as
/// opposed to an event it doesn't know (-1708). (A command waiting for its
/// answer can't be tried this way: an event sent to oneself can't wait.)
struct AgentAppleEventTests {
    /// The error the event gets, thrown or in its reply.
    private static func send(_ eventID: String) async -> Int32? {
        let code = { (text: String) in text.utf8.reduce(FourCharCode(0)) { $0 << 8 | FourCharCode($1) } }
        return await Task.detached {
            let event = NSAppleEventDescriptor(
                eventClass: code("Ombr"),
                eventID: code(eventID),
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            do {
                let reply = try event.sendEvent(options: [.waitForReply], timeout: 10)
                return reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value
            } catch {
                return Int32((error as NSError).code)
            }
        }.value
    }

    @Test func theSdefDefinesTheEvents() async {
        #expect(await Self.send("OpAd") == Int32(errAEDescNotFound))
        #expect(await Self.send("Zzzz") == Int32(errAEEventNotHandled))
    }
}
