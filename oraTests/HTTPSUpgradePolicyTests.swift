import Foundation
@testable import Ora
import Testing

struct HTTPSUpgradePolicyTests {
    private let page = URL(string: "http://example.com/news?id=1#top")!
    private let certificateError = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)

    @Test func anHTTPPageIsTriedOverHTTPS() {
        var policy = HTTPSUpgradePolicy()
        #expect(policy.upgrade(page, httpMethod: "GET") == URL(string: "https://example.com/news?id=1#top"))
    }

    @Test func httpsPostsAndExplicitPortsAreLeftAlone() throws {
        var policy = HTTPSUpgradePolicy()
        let https = try policy.upgrade(#require(URL(string: "https://example.com")), httpMethod: "GET")
        let post = policy.upgrade(page, httpMethod: "POST")
        let port = try policy.upgrade(#require(URL(string: "http://example.com:8080")), httpMethod: "GET")
        #expect(https == nil && post == nil && port == nil)
    }

    @Test func localNetworkAddressesAreLeftAlone() {
        for host in ["localhost", "nas", "192.168.1.10", "::1", "printer.local", "nas.lan", "box.home.arpa"] {
            #expect(!HTTPSUpgradePolicy.isPublic(host), "\(host)")
        }
        #expect(HTTPSUpgradePolicy.isPublic("www.worldgeekwide.fr"))
    }

    @Test func aFailedHTTPSAttemptFallsBackToHTTPOnce() {
        var policy = HTTPSUpgradePolicy()
        let upgraded = policy.upgrade(page, httpMethod: "GET")

        let fallback = policy.fallback(afterFailing: upgraded, error: certificateError)
        let retried = policy.upgrade(page, httpMethod: "GET")

        #expect(fallback == page)
        #expect(retried == nil)
    }

    @Test func otherFailuresDoNotFallBack() {
        var policy = HTTPSUpgradePolicy()
        let upgraded = policy.upgrade(page, httpMethod: "GET")
        let notFound = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        #expect(policy.fallback(afterFailing: upgraded, error: notFound) == nil)
    }

    @Test func aRedirectBackToHTTPKeepsTheSiteOnHTTP() throws {
        var policy = HTTPSUpgradePolicy()
        _ = policy.upgrade(page, httpMethod: "GET")

        let redirected = try policy.upgrade(#require(URL(string: "http://example.com/news")), httpMethod: "GET")
        let later = policy.upgrade(page, httpMethod: "GET")

        #expect(redirected == nil && later == nil)
    }

    @Test func aSuccessfulHTTPSPageKeepsUpgradingTheSite() throws {
        var policy = HTTPSUpgradePolicy()
        _ = policy.upgrade(page, httpMethod: "GET")
        policy.navigationCommitted()

        let next = try policy.upgrade(#require(URL(string: "http://example.com/other")), httpMethod: "GET")
        #expect(next == URL(string: "https://example.com/other"))
    }
}
