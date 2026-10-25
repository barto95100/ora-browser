import Foundation
@testable import Ora
import Testing

// MARK: - SiteOrigin

struct SiteOriginTests {
    @Test func defaultPortsAreNormalizedAway() throws {
        let explicit = try #require(SiteOrigin(string: "https://meet.example.com:443"))
        let implicit = try #require(SiteOrigin(string: "https://meet.example.com"))
        let fromWebKit = try #require(SiteOrigin(scheme: "https", host: "meet.example.com", port: 0))

        #expect(explicit == implicit)
        #expect(fromWebKit == implicit)
        #expect(implicit.description == "https://meet.example.com")
    }

    @Test func customPortIsKept() throws {
        let origin = try #require(SiteOrigin(string: "http://localhost:8080/some/path?q=1"))

        #expect(origin.port == 8080)
        #expect(origin.description == "http://localhost:8080")
    }

    @Test func schemeAndHostAreCaseInsensitive() throws {
        let upper = try #require(SiteOrigin(string: "HTTPS://Meet.Example.COM/"))
        let lower = try #require(SiteOrigin(string: "https://meet.example.com"))

        #expect(upper == lower)
    }

    @Test func httpAndHttpsAreDifferentOrigins() throws {
        let http = try #require(SiteOrigin(string: "http://example.com"))
        let https = try #require(SiteOrigin(string: "https://example.com"))

        #expect(http != https)
    }

    @Test func descriptionRoundTrips() throws {
        let origin = try #require(SiteOrigin(string: "https://example.com:8443"))

        #expect(SiteOrigin(string: origin.description) == origin)
    }

    @Test func displayNameRevealsInsecureSchemesAndCustomPorts() throws {
        let secure = try #require(SiteOrigin(string: "https://meet.example.com"))
        let insecure = try #require(SiteOrigin(string: "http://meet.example.com"))
        let customPort = try #require(SiteOrigin(string: "https://meet.example.com:8443"))

        #expect(secure.displayName == "meet.example.com")
        #expect(insecure.displayName == "http://meet.example.com")
        #expect(customPort.displayName == "https://meet.example.com:8443")
    }

    @Test func urlsWithoutHostAreRejected() {
        #expect(SiteOrigin(string: "about:blank") == nil)
        #expect(SiteOrigin(scheme: "https", host: "", port: nil) == nil)
    }
}

// MARK: - SitePermissions

struct SitePermissionsTests {
    @Test func combinedDecisionDeniesIfAnyCapabilityIsDenied() {
        let permissions = SitePermissions(camera: .allow, microphone: .deny)

        #expect(permissions.decision(for: [.camera, .microphone]) == .deny)
        #expect(permissions.decision(for: [.camera]) == .allow)
    }

    @Test func combinedDecisionAllowsOnlyIfEveryCapabilityIsAllowed() {
        let partial = SitePermissions(camera: .allow, microphone: .ask)
        let full = SitePermissions(camera: .allow, microphone: .allow)

        #expect(partial.decision(for: [.camera, .microphone]) == .ask)
        #expect(full.decision(for: [.camera, .microphone]) == .allow)
    }

    @Test func emptyRequestAsks() {
        #expect(SitePermissions(camera: .allow, microphone: .allow).decision(for: []) == .ask)
    }

    @Test func missingKeysDecodeAsAsk() throws {
        let data = Data(#"{"camera":"allow"}"#.utf8)
        let permissions = try JSONDecoder().decode(SitePermissions.self, from: data)

        #expect(permissions.camera == .allow)
        #expect(permissions.microphone == .ask)
    }
}

// MARK: - SitePermissionStore

struct SitePermissionStoreTests {
    private let space = UUID()
    private let otherSpace = UUID()
    private let origin = SiteOrigin(scheme: "https", host: "meet.example.com", port: nil) ?? {
        preconditionFailure("valid test origin")
    }()

    /// A store backed by its own throwaway defaults suite.
    private func makeStore(suite: String = "SitePermissionStoreTests.\(UUID().uuidString)")
        -> (SitePermissionStore, UserDefaults)
    {
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("could not create defaults suite \(suite)")
        }
        defaults.removePersistentDomain(forName: suite)
        return (SitePermissionStore(defaults: defaults), defaults)
    }

    @Test func unknownSiteAsks() {
        let (store, _) = makeStore()

        #expect(store.permissions(for: origin, in: space, isPrivate: false).isUndecided)
    }

    @Test func permissionsAreScopedPerSpace() {
        let (store, _) = makeStore()

        store.setState(.allow, for: [.camera], origin: origin, in: space, isPrivate: false)

        #expect(store.permissions(for: origin, in: space, isPrivate: false).camera == .allow)
        #expect(store.permissions(for: origin, in: otherSpace, isPrivate: false).camera == .ask)
    }

    @Test func permissionsArePersisted() {
        let suite = "SitePermissionStoreTests.\(UUID().uuidString)"
        let (store, defaults) = makeStore(suite: suite)

        store.setState(.deny, for: [.camera, .microphone], origin: origin, in: space, isPrivate: false)
        let reloaded = SitePermissionStore(defaults: defaults)

        #expect(reloaded.permissions(for: origin, in: space, isPrivate: false) ==
            SitePermissions(camera: .deny, microphone: .deny))
    }

    @Test func privateBrowsingIsNeverPersisted() {
        let suite = "SitePermissionStoreTests.\(UUID().uuidString)"
        let (store, defaults) = makeStore(suite: suite)

        store.setState(.allow, for: [.camera], origin: origin, in: space, isPrivate: true)

        #expect(store.permissions(for: origin, in: space, isPrivate: true).camera == .allow)
        #expect(store.permissions(for: origin, in: space, isPrivate: false).camera == .ask)
        #expect(SitePermissionStore(defaults: defaults).permissions(for: origin, in: space, isPrivate: true)
            .isUndecided)
    }

    @Test func resettingASiteRemovesIt() {
        let (store, _) = makeStore()

        store.setState(.allow, for: [.camera], origin: origin, in: space, isPrivate: false)
        store.removePermissions(for: origin, in: space, isPrivate: false)

        #expect(store.permissionsBySpace[space] == nil)
    }

    @Test func removingASpaceForgetsItsPermissions() {
        let (store, _) = makeStore()

        store.setState(.allow, for: [.camera], origin: origin, in: space, isPrivate: false)
        store.setState(.allow, for: [.camera], origin: origin, in: otherSpace, isPrivate: false)
        store.removeAll(in: space)

        #expect(store.permissions(for: origin, in: space, isPrivate: false).isUndecided)
        #expect(store.permissions(for: origin, in: otherSpace, isPrivate: false).camera == .allow)
    }
}
