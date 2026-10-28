import Foundation
@testable import Ora
import Testing

struct WebNotificationTests {
    private let origin = URL(string: "https://example.com")

    @Test func permissionNamesFollowTheWebStandard() {
        #expect(WebNotificationBridge.permissionName(for: .grant) == "granted")
        #expect(WebNotificationBridge.permissionName(for: .deny) == "denied")
        #expect(WebNotificationBridge.permissionName(for: .prompt) == "default")
    }

    @Test func aShowMessageBecomesANotification() throws {
        let notification = try #require(BrowserWebNotification(
            message: ["id": "3", "title": "New message", "body": "Hello", "tag": "", "silent": true],
            origin: origin
        ))
        #expect(notification.id == "3")
        #expect(notification.title == "New message")
        #expect(notification.body == "Hello")
        #expect(notification.tag == nil)
        #expect(notification.isSilent)
    }

    @Test func aShowMessageWithoutTitleIsIgnored() {
        #expect(BrowserWebNotification(message: ["id": "1"], origin: origin) == nil)
    }

    @Test func notificationsSharingATagReplaceEachOther() {
        let tabID = UUID()
        let first = BrowserWebNotification(id: "1", title: "A", body: "", tag: "chat", isSilent: false, origin: origin)
        let second = BrowserWebNotification(id: "2", title: "B", body: "", tag: "chat", isSilent: false, origin: origin)
        #expect(
            WebNotificationCenter.requestIdentifier(tabID: tabID, notification: first)
                == WebNotificationCenter.requestIdentifier(tabID: tabID, notification: second)
        )
    }

    @Test func untaggedNotificationsAreKeptApart() {
        let tabID = UUID()
        let first = BrowserWebNotification(id: "1", title: "A", body: "", tag: nil, isSilent: false, origin: origin)
        let second = BrowserWebNotification(id: "2", title: "A", body: "", tag: nil, isSilent: false, origin: origin)
        #expect(
            WebNotificationCenter.requestIdentifier(tabID: tabID, notification: first)
                != WebNotificationCenter.requestIdentifier(tabID: tabID, notification: second)
        )
    }

    @Test func savedSitesFromBeforeNotificationsAskForThem() throws {
        let data = Data(#"{"camera":"allow","microphone":"deny"}"#.utf8)
        let permissions = try JSONDecoder().decode(SitePermissions.self, from: data)
        #expect(permissions.camera == .allow)
        #expect(permissions.notifications == .ask)
    }
}
