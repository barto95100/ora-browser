import AppKit
import UserNotifications

/// Shows web notifications as macOS notifications, like Safari, and brings the
/// user back to their tab when one is clicked. Used from the main actor;
/// macOS calls its delegate methods on its own queue.
@MainActor
final class WebNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WebNotificationCenter()

    private struct WeakTab {
        weak var tab: Tab?
    }

    /// Tabs that showed notifications, to come back to them on a click.
    private var tabs: [UUID: WeakTab] = [:]

    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    func install() {
        center.delegate = self
    }

    /// Asks macOS, the first time only, to let Ombre show notifications.
    func requestAuthorizationIfNeeded() {
        // The tests' app never asks (it would be a new app to the system).
        guard !TestHost.isActive else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(_ notification: BrowserWebNotification, from tab: Tab) {
        tabs[tab.id] = WeakTab(tab: tab)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if let site = notification.origin.flatMap(SiteOrigin.init(url:)) {
            content.subtitle = site.displayName
            content.threadIdentifier = site.description
        }
        if !notification.isSilent {
            content.sound = .default
        }
        content.userInfo = [
            Self.tabIDKey: tab.id.uuidString,
            Self.notificationIDKey: notification.id
        ]
        let identifier = Self.requestIdentifier(tabID: tab.id, notification: notification)
        notificationRequests[Self.key(tabID: tab.id, notificationID: notification.id)] = identifier
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func close(_ notificationID: String, from tab: Tab) {
        guard let identifier = notificationRequests.removeValue(
            forKey: Self.key(tabID: tab.id, notificationID: notificationID)
        ) else { return }
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Request identifier of a page's notification → macOS request identifier.
    private var notificationRequests: [String: String] = [:]

    /// macOS identifier of a notification: one per tag, so a notification
    /// replaces the previous one of its tab with the same tag, as the web
    /// standard says.
    nonisolated static func requestIdentifier(tabID: UUID, notification: BrowserWebNotification) -> String {
        if let tag = notification.tag {
            return "\(tabID.uuidString)/tag/\(tag)"
        }
        return "\(tabID.uuidString)/id/\(notification.id)"
    }

    private nonisolated static let tabIDKey = "tabID"
    private nonisolated static let notificationIDKey = "notificationID"

    private static func key(tabID: UUID, notificationID: String) -> String {
        "\(tabID.uuidString)/\(notificationID)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown even while Ombre is in front, like Safari: the tab is often not the one in view.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Called back once on the main queue below.
        nonisolated(unsafe) let completionHandler = completionHandler
        let userInfo = response.notification.request.content.userInfo
        let tabID = (userInfo[Self.tabIDKey] as? String).flatMap(UUID.init(uuidString:))
        let notificationID = userInfo[Self.notificationIDKey] as? String
        let isClick = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        // A task reminder (see `TaskReminders`): its space's list.
        if userInfo[TaskReminders.taskIDKey] != nil {
            let spaceID = (userInfo[TaskReminders.spaceIDKey] as? String).flatMap(UUID.init(uuidString:))
            DispatchQueue.main.async {
                if isClick {
                    NSApp.activate()
                    NotificationCenter.default.post(
                        name: .openTaskReminder,
                        object: nil,
                        userInfo: spaceID.map { ["spaceID": $0] } ?? [:]
                    )
                }
                completionHandler()
            }
            return
        }
        DispatchQueue.main.async {
            if isClick, let tabID {
                self.openTab(tabID, notificationID: notificationID)
            }
            completionHandler()
        }
    }

    /// A click on a notification: its tab comes to the front, in its window,
    /// and the page is told (it may show the message the notification was about).
    private func openTab(_ tabID: UUID, notificationID: String?) {
        NSApp.activate()
        guard let tab = tabs[tabID]?.tab, let tabManager = tab.tabManager else { return }
        tabManager.activateTab(id: tabID)
        // The page is put in its window once the tab is shown.
        DispatchQueue.main.async {
            if let window = tab.browserPage?.window {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            if let notificationID {
                tab.browserPage?.dispatchNotificationEvent("click", notificationID: notificationID)
            }
        }
    }
}
