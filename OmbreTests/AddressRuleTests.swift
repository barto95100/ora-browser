import Foundation
@testable import Ombre
import Testing

/// Settings › Address Rules: what a rule takes, and which one wins.
struct AddressRuleTests {
    private let work = UUID()
    private let home = UUID()
    private let other = UUID()

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private func rule(_ input: String, subdomains: Bool = false, space: UUID) throws -> AddressRule {
        try #require(AddressRule.parse(input, includesSubdomains: subdomains, spaceID: space))
    }

    // MARK: - Typed patterns

    @Test func parsesWhatIsTyped() throws {
        let star = try rule("*.sccnf.fr", space: work)
        #expect(star.kind == .domainAndSubdomains)
        #expect(star.pattern == "sccnf.fr")
        #expect(star.display == "*.sccnf.fr")

        let domain = try rule("https://www.HACF.fr/", space: home)
        #expect(domain.kind == .domain)
        #expect(domain.pattern == "hacf.fr")

        let withSubdomains = try rule("hacf.fr", subdomains: true, space: home)
        #expect(withSubdomains.kind == .domainAndSubdomains)

        let prefix = try rule("github.com/barto95100", space: work)
        #expect(prefix.kind == .prefix)
        #expect(prefix.pattern == "github.com/barto95100")
        #expect(prefix.domain == "github.com")
    }

    @Test(arguments: ["", "   ", "localhost", "*.", ".fr", "https://"])
    func refusesWhatIsNotAnAddress(input: String) {
        #expect(AddressRule.parse(input, includesSubdomains: false, spaceID: UUID()) == nil)
    }

    // MARK: - Matching

    @Test func aDomainTakesItselfAndWwwOnly() throws {
        let hacf = try rule("hacf.fr", space: home)
        #expect(try hacf.matches(url("https://hacf.fr/forum")))
        #expect(try hacf.matches(url("http://www.hacf.fr")))
        #expect(try !hacf.matches(url("https://forum.hacf.fr")))
        #expect(try !hacf.matches(url("https://nothacf.fr")))
    }

    @Test func subdomainsTakeTheDomainToo() throws {
        let sccnf = try rule("*.sccnf.fr", space: work)
        #expect(try sccnf.matches(url("https://sccnf.fr")))
        #expect(try sccnf.matches(url("https://intranet.sccnf.fr/a")))
        #expect(try sccnf.matches(url("https://a.b.sccnf.fr")))
        #expect(try !sccnf.matches(url("https://notsccnf.fr")))
        #expect(try !sccnf.matches(url("https://sccnf.fr.evil.com")))
    }

    @Test func aPrefixStopsAtAPathBoundary() throws {
        let doc = try rule("example.com/doc", space: work)
        #expect(try doc.matches(url("https://example.com/doc")))
        #expect(try doc.matches(url("https://example.com/doc/page?x=1")))
        #expect(try doc.matches(url("http://www.example.com/doc#top")))
        #expect(try !doc.matches(url("https://example.com/docs")))
        #expect(try !doc.matches(url("https://example.com/")))
    }

    /// The domain is not case-sensitive, a path is (as on the web).
    @Test func aPrefixKeepsTheCaseOfItsPath() throws {
        let mine = try rule("GitHub.com/Barto95100", space: work)
        #expect(mine.pattern == "github.com/Barto95100")
        #expect(try mine.matches(url("https://github.com/Barto95100/ora-browser")))
        #expect(try !mine.matches(url("https://github.com/barto95100/ora-browser")))
    }

    @Test func theRootsDotIsTheSameDomain() throws {
        let hacf = try rule("hacf.fr.", space: home)
        #expect(hacf.pattern == "hacf.fr")
        #expect(try hacf.matches(url("https://hacf.fr./forum")))
    }

    /// The web writes `example.com/?lang=fr`: typed with or without `/`.
    @Test func aQueryMakesAPrefix() throws {
        let search = try rule("example.com?lang=fr", space: work)
        #expect(search.kind == .prefix)
        #expect(search.domain == "example.com")
        #expect(try search.matches(url("https://example.com/?lang=fr")))
        #expect(try search.matches(url("https://example.com?lang=fr")))
        #expect(try !search.matches(url("https://example.com/?lang=en")))
    }

    /// Web addresses carry it in punycode: as such when macOS gives it,
    /// else refused (never a rule that can't match).
    @Test func aDomainWithAccentsIsPunycodeOrRefused() throws {
        let books = AddressRule.parse("bücher.de", includesSubdomains: false, spaceID: home)
        if let books {
            #expect(books.pattern == "xn--bcher-kva.de")
            #expect(try books.matches(url("https://xn--bcher-kva.de/")))
        }
        let typedAsTheWebHasIt = try rule("xn--bcher-kva.de", space: home)
        #expect(try typedAsTheWebHasIt.matches(url("https://xn--bcher-kva.de/a")))
    }

    @Test(arguments: ["exa mple.com", "https://a*.example.com", "ex_ample.com"])
    func refusesWhatNoAddressHas(input: String) {
        #expect(AddressRule.parse(input, includesSubdomains: false, spaceID: UUID()) == nil)
    }

    @Test func theQuickRuleOfAnIPAddressIsItself() throws {
        let box = try #require(AddressRule.quickRule(for: url("http://192.168.1.10/admin"), spaceID: home))
        #expect(box.kind == .domain)
    }

    /// `*.168.1.10` would take `192.168.1.10`: an IP address is itself only.
    @Test func anIPAddressHasNoSubdomains() throws {
        let box = try rule("192.168.1.10", subdomains: true, space: home)
        #expect(box.kind == .domain)
        #expect(try box.matches(url("http://192.168.1.10:8080/admin")))
    }

    @Test(arguments: ["file:///Users/x/hacf.fr", "ftp://hacf.fr/a", "about:blank", "ombre://hacf.fr"])
    func onlyWebAddresses(address: String) throws {
        let hacf = try rule("hacf.fr", subdomains: true, space: home)
        #expect(try !hacf.matches(url(address)))
    }

    @Test func portsAndSignInPartsAreNotTheDomain() throws {
        let hacf = try rule("hacf.fr", space: home)
        #expect(try hacf.matches(url("https://user@hacf.fr:8443/a")))
    }

    // MARK: - The most precise wins

    @Test func theMostPreciseRuleWins() throws {
        let rules = try [
            rule("*.example.com", space: home),
            rule("app.example.com", space: work),
            rule("app.example.com/admin", space: other),
            rule("*.app.example.com", space: home)
        ]
        let spaces: Set = [work, home, other]
        func space(for address: String) throws -> UUID? {
            try AddressRule.rule(for: url(address), in: rules, spaceIDs: spaces)?.spaceID
        }
        // A prefix over a domain.
        #expect(try space(for: "https://app.example.com/admin/users") == other)
        // A domain over the subdomains of that same domain.
        #expect(try space(for: "https://app.example.com/home") == work)
        // The deeper subdomains over the shorter.
        #expect(try space(for: "https://x.app.example.com") == home)
        #expect(try space(for: "https://blog.example.com") == home)
        #expect(try space(for: "https://example.org") == nil)
    }

    /// Order does not matter, only precision.
    @Test func precisionNotOrder() throws {
        let broad = try rule("*.sccnf.fr", space: home)
        let narrow = try rule("intranet.sccnf.fr", space: work)
        let address = try url("https://intranet.sccnf.fr")
        for rules in [[broad, narrow], [narrow, broad]] {
            #expect(AddressRule.rule(for: address, in: rules, spaceIDs: [work, home])?.spaceID == work)
        }
    }

    /// A deleted space's rules no longer apply.
    @Test func aRuleOfADeletedSpaceIsIgnored() throws {
        let rules = try [rule("*.sccnf.fr", space: work), rule("sccnf.fr", space: other)]
        let address = try url("https://sccnf.fr")
        #expect(AddressRule.rule(for: address, in: rules, spaceIDs: [work])?.spaceID == work)
        #expect(AddressRule.rule(for: address, in: rules, spaceIDs: []) == nil)
    }

    // MARK: - Adding

    @Test func addingTheSameAddressMovesItsSpace() throws {
        var rules = try [rule("hacf.fr", space: home)]
        rules = try AddressRule.adding(rule("https://www.hacf.fr", space: work), to: rules)
        #expect(rules.count == 1)
        #expect(rules.first?.spaceID == work)
        rules = try AddressRule.adding(rule("*.hacf.fr", space: home), to: rules)
        #expect(rules.count == 2)
    }

    @Test func theTabsQuickRuleTakesItsDomainAndSubdomains() throws {
        let quick = try #require(AddressRule.quickRule(for: url("https://www.hacf.fr/forum/t/1"), spaceID: home))
        #expect(quick.kind == .domainAndSubdomains)
        #expect(quick.pattern == "hacf.fr")
        #expect(try AddressRule.quickRule(for: url("about:blank"), spaceID: home) == nil)
    }

    @Test func rulesKeepAcrossLaunches() throws {
        let rules = try [rule("*.sccnf.fr", space: work), rule("github.com/barto95100", space: home)]
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([AddressRule].self, from: data) == rules)
    }
}

/// When a link goes to another space.
struct AddressRoutingTests {
    private let work = UUID()
    private let home = UUID()

    private var rules: [AddressRule] {
        [AddressRule(kind: .domainAndSubdomains, pattern: "sccnf.fr", spaceID: work)]
    }

    @Test func aLinkForAnotherSpaceGoesThere() {
        let decision = AddressRouting.decide(
            url: URL(string: "https://intranet.sccnf.fr"), currentSpaceID: home, isPrivate: false,
            rules: rules, spaceIDs: [work, home]
        )
        #expect(decision == .space(work))
    }

    @Test func alreadyInItsSpaceItStays() {
        let decision = AddressRouting.decide(
            url: URL(string: "https://sccnf.fr"), currentSpaceID: work, isPrivate: false,
            rules: rules, spaceIDs: [work, home]
        )
        #expect(decision == .stay)
    }

    @Test func neverInAPrivateWindow() {
        let decision = AddressRouting.decide(
            url: URL(string: "https://sccnf.fr"), currentSpaceID: home, isPrivate: true,
            rules: rules, spaceIDs: [work, home]
        )
        #expect(decision == .stay)
    }

    @Test func noRuleNoAddressItStays() {
        #expect(AddressRouting.decide(
            url: URL(string: "https://example.org"), currentSpaceID: home, isPrivate: false,
            rules: rules, spaceIDs: [work, home]
        ) == .stay)
        #expect(AddressRouting.decide(
            url: nil, currentSpaceID: home, isPrivate: false, rules: rules, spaceIDs: [work, home]
        ) == .stay)
    }

    @Test func theTestFieldAddsHttps() {
        #expect(AddressRulesTester.url(from: "intranet.sccnf.fr/a")?.absoluteString == "https://intranet.sccnf.fr/a")
        #expect(AddressRulesTester.url(from: "  ") == nil)
        #expect(AddressRulesTester.url(from: "ftp://x.fr") == nil)
    }
}
