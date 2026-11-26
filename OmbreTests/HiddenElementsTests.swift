import Foundation
@testable import Ombre
import Testing
import WebKit

/// Elements hidden per site and per space (element picker), and the WebKit
/// rules that hide them before the page shows.
@MainActor
struct HiddenElementsTests {
    private let space = UUID()
    private let otherSpace = UUID()

    private func makeStore() throws -> (HiddenElementsStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "HiddenElementsTests-\(UUID().uuidString)"))
        return (HiddenElementsStore(defaults: defaults, storageKey: "hidden"), defaults)
    }

    private func element(_ selector: String) -> HiddenElement {
        HiddenElement(selector: selector, label: "div", date: Date(timeIntervalSince1970: 0))
    }

    @Test func elementsArePerSiteAndPerSpace() throws {
        let (store, _) = try makeStore()
        #expect(store.hide(element("#ad"), onSite: "example.com", in: space))
        store.hide(element(".banner"), onSite: "example.com", in: space)
        store.hide(element("#ad"), onSite: "other.org", in: space)

        #expect(store.elements(onSite: "example.com", in: space).map(\.selector) == ["#ad", ".banner"])
        #expect(store.elements(onSite: "other.org", in: space).map(\.selector) == ["#ad"])
        // Another space hides nothing.
        #expect(store.elements(onSite: "example.com", in: otherSpace).isEmpty)
        // The same element again: listed once.
        #expect(!store.hide(element("#ad"), onSite: "example.com", in: space))
        #expect(store.elements(onSite: "example.com", in: space).count == 2)
    }

    @Test func shownAgainOneOrAllOfASite() throws {
        let (store, _) = try makeStore()
        store.hide(element("#ad"), onSite: "example.com", in: space)
        store.hide(element(".banner"), onSite: "example.com", in: space)
        store.hide(element("#ad"), onSite: "other.org", in: space)

        store.show("#ad", onSite: "example.com", in: space)
        #expect(store.elements(onSite: "example.com", in: space).map(\.selector) == [".banner"])

        store.showAll(onSite: "example.com", in: space)
        #expect(store.elements(in: space).keys.sorted() == ["other.org"])

        #expect(store.removeAll(in: space))
        #expect(store.elements(in: space).isEmpty)
        #expect(!store.removeAll(in: space))
    }

    /// Its words first, else its kind; elements kept before their words
    /// were: a kind told by their label, never the selector again.
    @Test func titlesAreReadable() throws {
        let named = HiddenElement(selector: "#x", label: "div#x", date: .now, name: "Related stories", kind: "sidebar")
        #expect(named.title == "Related stories")
        let kindOnly = HiddenElement(selector: "nav", label: "nav", date: .now, name: "", kind: "navigation")
        #expect(kindOnly.name == nil)
        #expect(kindOnly.title == HiddenElement.kindTitle("navigation"))
        // Saved by the first version, without words nor kind.
        let old = try JSONDecoder().decode(HiddenElement.self, from: Data(
            #"{"selector":"div.cs-sidebar__inner","label":"div.cs-sidebar__inner","date":0}"#.utf8
        ))
        #expect(old.title == HiddenElement.kindTitle("sidebar"))
        #expect(HiddenElement.kind(fromLabel: "div#cookie-consent") == "cookies")
        #expect(HiddenElement.kind(fromLabel: "footer") == "footer")
        #expect(HiddenElement.kind(fromLabel: "div.wrapper") == nil)
        #expect(HiddenElement(selector: "div", label: "div.wrapper", date: .now).title != "div.wrapper")
    }

    @Test func keptAcrossLaunches() throws {
        let (store, defaults) = try makeStore()
        store.hide(element("#ad"), onSite: "example.com", in: space)

        let relaunched = HiddenElementsStore(defaults: defaults, storageKey: "hidden")
        #expect(relaunched.elements(onSite: "example.com", in: space) == [element("#ad")])
    }

    /// One rule per element (an invalid selector would void a group), for
    /// the site and its subdomains.
    @Test func rulesHideEachElementOnItsSite() throws {
        let rules = HiddenElementRuleLists.rules([
            "example.com": [element("#ad"), element("div.banner")],
            "other.org": [element("aside")]
        ])
        #expect(rules.count == 3)
        let first = try #require(rules.first)
        let trigger = try #require(first["trigger"] as? [String: Any])
        let action = try #require(first["action"] as? [String: Any])
        #expect(trigger["if-domain"] as? [String] == ["*example.com"])
        #expect(trigger["url-filter"] as? String == ".*")
        #expect(action["type"] as? String == "css-display-none")
        #expect(action["selector"] as? String == "#ad")
        #expect((rules.last?["trigger"] as? [String: Any])?["if-domain"] as? [String] == ["*other.org"])
        // Nothing hidden: no list at all.
        #expect(HiddenElementRuleLists.encodedRules([:]) == nil)
    }

    /// WebKit wants ASCII domains: an international site in its `xn--` form.
    @Test func internationalSitesInTheirASCIIForm() {
        #expect(HiddenElementRuleLists.ruleDomain("Example.COM") == "example.com")
        #expect(HiddenElementRuleLists.ruleDomain("exämple.de") == "xn--exmple-cua.de")
        let rules = HiddenElementRuleLists.rules(["exämple.de": [element("#ad")]])
        #expect((rules.first?["trigger"] as? [String: Any])?["if-domain"] as? [String] == ["*xn--exmple-cua.de"])
    }

    /// A rule WebKit refuses would void every element of the space: it is
    /// compiled alone first, and not kept if it fails.
    @Test func aRuleThatCannotBeCompiledIsNotKept() async {
        let lists = HiddenElementRuleLists(store: HiddenElementsStore(
            defaults: UserDefaults(suiteName: "HiddenElementsTests-\(UUID().uuidString)") ?? .standard,
            storageKey: "hidden"
        ))
        let refused = await withCheckedContinuation { continuation in
            // A site WebKit's rules can't name.
            lists.accepts(element("#ad"), onSite: "exa mple") { continuation.resume(returning: $0) }
        }
        let accepted = await withCheckedContinuation { continuation in
            lists.accepts(element("#sidebar > div.panel"), onSite: "example.com") { continuation.resume(returning: $0) }
        }
        #expect(!refused)
        #expect(accepted)
    }

    /// The same elements at the next launch: the same compiled list; others: another.
    @Test func oneListVersionPerContent() throws {
        let rules = try #require(HiddenElementRuleLists.encodedRules(["example.com": [element("#ad")]]))
        let other = try #require(HiddenElementRuleLists.encodedRules(["example.com": [element("#ads")]]))
        let first = HiddenElementRuleLists.identifier(for: space, rules: rules)
        #expect(first == HiddenElementRuleLists.identifier(for: space, rules: rules))
        #expect(first != HiddenElementRuleLists.identifier(for: space, rules: other))
        #expect(first.hasPrefix(HiddenElementRuleLists.identifierPrefix(for: space)))
        // Not counted as blocked content by the shield.
        #expect(!BrowserPrivacyService.blocksContent(ruleListIdentifier: first))
    }

    /// WebKit compiles them, quotes and attributes included.
    @Test func webKitCompilesTheRules() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HiddenRules-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ruleStore = try #require(WKContentRuleListStore(url: folder))
        let encoded = try #require(HiddenElementRuleLists.encodedRules([
            "example.com": [
                element(#"div[data-testid="panel \"main\""] > section:nth-of-type(2)"#),
                element("#sidebar")
            ]
        ]))
        let list = try await ruleStore.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: encoded)
        #expect(list != nil)
    }

    /// Hidden from the first load on the site and its subdomains, by WebKit
    /// (no style in the page); shown on another site.
    @Test func hiddenFromTheFirstLoadOnTheSiteOnly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HiddenRules-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ruleStore = try #require(WKContentRuleListStore(url: folder))
        let encoded = try #require(HiddenElementRuleLists.encodedRules(["example.com": [element("#sidebar")]]))
        let list = try await ruleStore.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: encoded)
        let check = """
        const sidebar = document.getElementById("sidebar");
        return [
            getComputedStyle(sidebar).display, sidebar.getAttribute("style"), document.querySelectorAll("style").length
        ];
        """
        for address in ["https://example.com/", "https://news.example.com/a"] {
            let page = try await OffscreenPage(
                #"<div id="sidebar">x</div>"#,
                ruleList: list,
                baseURL: URL(string: address)
            )
            let value = try await page.run(check) as? [Any]
            #expect(value?.first as? String == "none", "\(address)")
            #expect(value?[1] is NSNull, "no inline style")
            #expect(value?[2] as? Int == 0, "no style element")
        }
        let elsewhere = try await OffscreenPage(
            #"<div id="sidebar">x</div>"#, ruleList: list, baseURL: URL(string: "https://example.org/")
        )
        #expect(try await (elsewhere.run(check) as? [Any])?.first as? String == "block")
    }
}
