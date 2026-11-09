import Foundation
@testable import Ombre
import Testing

/// What an extension is allowed, refused, and who it is (SEC-14, SEC-16).
struct ExtensionHardeningTests {
    private func record() -> ExtensionRecord {
        var record = ExtensionRecord(source: .file(packagePath: "/tmp/x.zip"), name: "Test", appName: nil)
        record.grantedPermissions = ["storage"]
        return record
    }

    /// A refusal is remembered: the extension can't ask in a loop.
    @Test func aRefusedPermissionIsNotAskedAgain() {
        var record = record()
        #expect(record.undecidedPermissions(["storage", "tabs", "history"]) == ["tabs", "history"])
        record.deny(["tabs", "history"])
        #expect(record.deniedPermissions == ["history", "tabs"])
        #expect(record.undecidedPermissions(["storage", "tabs", "history"]).isEmpty)
        #expect(record.undecidedPermissions(["bookmarks", "tabs"]) == ["bookmarks"])
    }

    /// Allowed later (an update the user accepts): no longer refused.
    @Test func allowingLiftsARefusal() {
        var record = record()
        record.deny(["tabs", "storage"])
        // Already allowed: never refused by that.
        #expect(record.deniedPermissions == ["tabs"])
        record.grant(["tabs"])
        #expect(record.grantedPermissions == ["storage", "tabs"])
        #expect(record.deniedPermissions.isEmpty)
    }

    /// Forgotten from Settings: it may ask again, without a reinstall.
    @Test func aForgottenRefusalCanBeAskedAgain() {
        var record = record()
        record.deny(["tabs", "history"])
        record.forgetRefusal(of: "tabs")
        #expect(record.deniedPermissions == ["history"])
        #expect(record.undecidedPermissions(["storage", "tabs", "history"]) == ["tabs"])
        #expect(!record.grantedPermissions.contains("tabs"))
        record.forgetRefusal(of: "bookmarks")
        #expect(record.deniedPermissions == ["history"])
    }

    /// Saved before refusals were remembered: none.
    @Test func olderRecordsHaveNoRefusals() throws {
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record())) as? [String: Any]
        saved?.removeValue(forKey: "deniedPermissions")
        let data = try JSONSerialization.data(withJSONObject: #require(saved))
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExtensionRecord.self, from: data)
        #expect(decoded.deniedPermissions.isEmpty)
        #expect(decoded.grantedPermissions == ["storage"])
    }

    /// Signed by the team recorded at install, or by any team for an
    /// extension installed before teams were recorded; never unsigned.
    @Test func theSameTeamMustSignIt() {
        #expect(SafariExtensionIdentity.accepts(team: "TEAM1", recorded: "TEAM1"))
        #expect(!SafariExtensionIdentity.accepts(team: "TEAM2", recorded: "TEAM1"))
        #expect(SafariExtensionIdentity.accepts(team: "TEAM1", recorded: nil))
        #expect(!SafariExtensionIdentity.accepts(team: nil, recorded: "TEAM1"))
        #expect(!SafariExtensionIdentity.accepts(team: nil, recorded: nil))
    }

    /// The app itself: signed by Ludo's team, or ad hoc on GitHub's runners
    /// (no team, refused like any re-signed copy).
    @Test func aTeamIsReadFromTheSignature() {
        let team = SafariExtensionIdentity.signingTeam(of: Bundle.main.bundleURL)
        #expect(team == nil || team == "Q76T6LDBBZ")
    }

    /// An extension from the Mac App Store: Apple re-signs it for its
    /// developer, whose team it keeps (uBlock Origin Lite: WY4R6PNRF6, not
    /// Apple's). Only on a Mac where it is installed (not GitHub's runners).
    static let appStoreExtension = URL(
        fileURLWithPath: "/Applications/uBlock Origin Lite.app/Contents/PlugIns/uBlock Origin Lite Extension.appex"
    )

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.appStoreExtension.path)))
    func anAppStoreExtensionKeepsItsDevelopersTeam() {
        let team = SafariExtensionIdentity.signingTeam(of: Self.appStoreExtension)
        #expect(team == "WY4R6PNRF6")
        #expect(SafariExtensionIdentity.accepts(team: team, recorded: nil))
        #expect(SafariExtensionIdentity.accepts(team: team, recorded: "WY4R6PNRF6"))
    }

    @Test func anUnsignedBundleHasNoTeam() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = folder.appendingPathComponent("Fake.appex/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundlePackageType": "XPC!"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Info.plist"))
        #expect(SafariExtensionIdentity.signingTeam(of: folder.appendingPathComponent("Fake.appex")) == nil)
    }
}
