import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// The Agent Actions panel's list: the session's commands, in memory,
    /// with what the log says and nothing more.
    @MainActor
    @Suite(.serialized)
    struct AgentActionsTests {
        private let terminal = AgentSender(key: "com.apple.Terminal", name: "Terminal")

        private func control(_ window: TabManagerTestWindow?, pageActions: Bool = false, answer: Bool? = true)
            -> AgentControl
        {
            let control = AgentControl()
            control.isAllowed = { true }
            control.allowsPageActions = { pageActions }
            control.ask = { _ in answer }
            control.tabManager = { window?.tabManager }
            return control
        }

        @Test func theSessionsCommandsAreListed() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                _ = await control.run(.listTabs, from: terminal)
                _ = await control.run(.activate("not-a-tab"), from: terminal)
                let actions = control.actions
                #expect(actions.count == 2)
                #expect(actions.map(\.app) == ["Terminal", "Terminal"])
                #expect(actions.map(\.command) == [AgentCommand.listTabs.title, AgentCommand.activate("").title])
                #expect(actions.first?.succeeded == true)
                #expect(actions.last?.succeeded == false)
                #expect(actions.last?.failure == AgentError.noTab.message)
                #expect(actions.allSatisfy { $0.host == nil && $0.tabID == nil })
            }
        }

        /// As the log: never the selector, the text filled in nor the code.
        @Test func neverASelectorATextNorCode() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window, pageActions: true)
                _ = await control.run(.fill(tab: nil, selector: "#secret-field", value: "hunter2"), from: terminal)
                _ = await control.run(.runScript(tab: nil, code: "return document.cookie"), from: terminal)
                #expect(control.actions.count == 2)
                for action in control.actions {
                    let shown = [action.app, action.command, action.host, action.tabTitle, action.failure]
                        .compactMap(\.self).joined(separator: " ")
                    #expect(!shown.contains("secret-field"))
                    #expect(!shown.contains("hunter2"))
                    #expect(!shown.contains("cookie"))
                }
            }
        }

        /// What a page said never stays: a script's error (its own text goes
        /// to the agent only), nor a reply's element or result.
        @Test func neitherAScriptsErrorNorAReplyIsKept() {
            let failed = AgentActionRecord(
                app: "Terminal", command: "JavaScript", host: "example.com", tabID: nil, tabTitle: "Example",
                result: .failure(.scriptFailed("hunter2 in the page"))
            )
            #expect(failed.failure == "The script failed.")
            let done = AgentActionRecord(
                app: "Terminal", command: "Fill In", host: "example.com", tabID: nil, tabTitle: "Example",
                result: .success(#"{"element":"input#secret-field","result":"hunter2"}"#)
            )
            #expect(done.succeeded)
            #expect(done.failure == nil)
            var loadFailed = AgentError.notLoaded
            loadFailed.loadError = "secret-host is down"
            let failedLoad = AgentActionRecord(
                app: "Terminal", command: "Read", host: nil, tabID: nil, tabTitle: nil, result: .failure(loadFailed)
            )
            #expect(failedLoad.failure == AgentError.notLoaded.message)
        }

        /// Refused before a session: not an action of the session.
        @Test func aRefusedAppHasNoActions() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window, answer: false)
                _ = await control.run(.listTabs, from: terminal)
                #expect(control.actions.isEmpty)
            }
        }

        /// In memory for the session only: Stop clears it.
        @Test func stopClearsTheList() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                _ = await control.run(.listTabs, from: terminal)
                #expect(!control.actions.isEmpty)
                control.stop()
                #expect(control.actions.isEmpty)
            }
        }

        @Test func theOldestGoPastTheLimit() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                for _ in 0 ..< AgentControl.maxActions {
                    _ = await control.run(.listTabs, from: terminal)
                }
                let oldest = try #require(control.actions.first?.id)
                let second = try #require(control.actions.dropFirst().first?.id)
                _ = await control.run(.activate("not-a-tab"), from: terminal)
                #expect(control.actions.count == AgentControl.maxActions)
                #expect(control.actions.first?.id == second)
                #expect(!control.actions.contains { $0.id == oldest })
                #expect(control.actions.last?.succeeded == false)
            }
        }

        @Test func everyCommandHasATitle() {
            let commands: [AgentCommand] = [
                .listTabs, .open(""), .activate(""), .close(""), .read(nil), .capture(nil),
                .click(tab: nil, selector: ""), .fill(tab: nil, selector: "", value: ""),
                .runScript(tab: nil, code: ""), .goBack(nil), .goForward(nil), .reload(nil),
                .wait(tab: nil, selector: nil, timeout: nil)
            ]
            let titles = Set(commands.map(\.title))
            #expect(titles.count == commands.count)
            #expect(!titles.contains(""))
        }
    }
}
