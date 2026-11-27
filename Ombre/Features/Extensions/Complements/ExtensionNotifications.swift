import Foundation
import os.log
@preconcurrency import UserNotifications

private let logger = Logger(category: "ExtensionComplements")

/// `chrome.notifications`, which WebKit lacks: an extension's notifications
/// as macOS notifications (Ombre's, under the extension's name), their
/// clicks, buttons and dismissals back to it, as in Chrome.
@MainActor
final class ExtensionNotifications {
    /// A notification as macOS shows it.
    struct Shown: Equatable {
        let identifier: String
        let extensionID: String
        let notificationID: String
        var title: String
        var subtitle: String
        var body: String
        var isSilent: Bool
        var buttons: [String]
        var image: Data?
        var imageType: String?
    }

    /// Where notifications go (the tests give their own).
    struct Presenter {
        var show: @MainActor (Shown) async -> Void
        var remove: @MainActor ([String]) -> Void
        /// Whether macOS lets Ombre show notifications.
        var isAllowed: @MainActor () async -> Bool
    }

    /// What a click, a button or a dismissal says (`WebNotificationCenter`).
    enum Response: Equatable {
        case click
        case button(Int)
        case dismiss
    }

    nonisolated static let extensionIDKey = "ombreExtensionID"
    nonisolated static let notificationIDKey = "ombreExtensionNotificationID"
    static let identifierPrefix = "ombre.extension/"
    /// Chrome shows two buttons at most.
    static let maxButtons = 2
    static let maxImageBytes = 5 << 20

    var presenter: Presenter
    /// An event for the extension (`ExtensionEvents`).
    var event: (_ extensionID: String, _ name: String, _ args: [Any]) -> Void = { _, _, _ in }

    /// Shown now, by extension then by its id: their options, as given.
    private var shown: [String: [String: [String: Any]]] = [:]

    init(presenter: Presenter = .system) {
        self.presenter = presenter
    }

    func handle(
        _ method: String,
        _ details: [String: Any],
        extensionID: String,
        extensionName: String?
    ) async throws -> Any? {
        switch method {
        case "create":
            let given = (details["notificationId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let id = given ?? UUID().uuidString
            let options = details["options"] as? [String: Any] ?? [:]
            let required = ["type", "iconUrl", "title", "message"]
            guard required.allSatisfy({ options[$0] is String }) else {
                let missing = "Some of the required properties are missing: " // not shown
                throw ExtensionComplementFailure.invalid(missing + "type, iconUrl, title and message.") // not shown
            }
            try await show(id, options, extensionID: extensionID, extensionName: extensionName)
            return id
        case "update":
            guard let id = details["notificationId"] as? String, let current = shown[extensionID]?[id] else {
                return false
            }
            let changes = details["options"] as? [String: Any] ?? [:]
            // Quietly, as in Chrome.
            try await show(
                id, current.merging(changes) { $1 }, extensionID: extensionID, extensionName: extensionName,
                isUpdate: true
            )
            return true
        case "clear":
            guard let id = details["notificationId"] as? String, shown[extensionID]?[id] != nil else { return false }
            close(id, extensionID: extensionID)
            event(extensionID, "notifications.onClosed", [id, false])
            return true
        case "getAll":
            return (shown[extensionID] ?? [:]).mapValues { _ in true }
        case "getPermissionLevel":
            return await presenter.isAllowed() ? "granted" : "denied"
        default:
            throw ExtensionComplementFailure.unknownCall("notifications.\(method)")
        }
    }

    private func show(
        _ id: String,
        _ options: [String: Any],
        extensionID: String,
        extensionName: String?,
        isUpdate: Bool = false
    ) async throws {
        let type = options["type"] as? String ?? "basic"
        guard ["basic", "image", "list", "progress"].contains(type) else {
            throw ExtensionComplementFailure.invalid("Invalid notification type: '\(type)'.") // not shown
        }
        var lines = [options["message"] as? String ?? ""]
        if type == "list" {
            for item in options["items"] as? [[String: Any]] ?? [] {
                let title = item["title"] as? String ?? "", message = item["message"] as? String ?? ""
                lines.append(message.isEmpty ? title : String(localized: "\(title): \(message)"))
            }
        }
        if type == "progress", let progress = options["progress"] as? Int {
            lines.append((Double(min(max(progress, 0), 100)) / 100).formatted(.percent))
        }
        if let context = options["contextMessage"] as? String, !context.isEmpty { lines.append(context) }
        let buttons = (options["buttons"] as? [[String: Any]] ?? []).prefix(Self.maxButtons)
            .map { $0["title"] as? String ?? "" }
        // The picture the extension read from its package (`image` for an
        // "image" notification, else its icon).
        let image = (options["imageData"] as? String ?? options["iconData"] as? String)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { $0.count <= Self.maxImageBytes ? $0 : nil }
        let imageType = options["imageData"] != nil ? options["imageType"] as? String : options["iconType"] as? String
        shown[extensionID, default: [:]][id] = options
        await presenter.show(Shown(
            identifier: Self.identifier(extensionID: extensionID, notificationID: id),
            extensionID: extensionID,
            notificationID: id,
            title: options["title"] as? String ?? "",
            subtitle: extensionName ?? "",
            body: lines.filter { !$0.isEmpty }.joined(separator: "\n"),
            isSilent: isUpdate || options["silent"] as? Bool == true,
            buttons: buttons,
            image: image,
            imageType: imageType
        ))
    }

    static func identifier(extensionID: String, notificationID: String) -> String {
        identifierPrefix + extensionID + "/" + notificationID
    }

    private func close(_ id: String, extensionID: String) {
        shown[extensionID]?[id] = nil
        presenter.remove([Self.identifier(extensionID: extensionID, notificationID: id)])
    }

    /// The user answered one (macOS): the extension is told, as in Chrome.
    func respond(_ response: Response, extensionID: String, notificationID id: String) {
        guard shown[extensionID]?[id] != nil else { return }
        shown[extensionID]?[id] = nil
        switch response {
        case .click: event(extensionID, "notifications.onClicked", [id])
        case let .button(index): event(extensionID, "notifications.onButtonClicked", [id, index])
        case .dismiss: event(extensionID, "notifications.onClosed", [id, true])
        }
    }

    /// The extension stopped or was removed: its notifications go.
    func forget(extensionID: String) {
        let ids = (shown.removeValue(forKey: extensionID) ?? [:]).keys
        if !ids.isEmpty { presenter.remove(ids.map { Self.identifier(extensionID: extensionID, notificationID: $0) }) }
    }
}

extension ExtensionNotifications.Presenter {
    /// macOS's notifications (none in the tests' app).
    static var system: ExtensionNotifications.Presenter {
        ExtensionNotifications.Presenter(
            show: { shown in
                guard !TestHost.isActive else { return }
                WebNotificationCenter.shared.requestAuthorizationIfNeeded()
                let center = UNUserNotificationCenter.current()
                let content = UNMutableNotificationContent()
                content.title = shown.title
                content.subtitle = shown.subtitle
                content.body = shown.body
                content.threadIdentifier = ExtensionNotifications.identifierPrefix + shown.extensionID
                if !shown.isSilent { content.sound = .default }
                content.userInfo = [
                    ExtensionNotifications.extensionIDKey: shown.extensionID,
                    ExtensionNotifications.notificationIDKey: shown.notificationID
                ]
                content.categoryIdentifier = ExtensionNotificationCategories.identifier(for: shown.buttons)
                // Before it shows: else, without its buttons.
                await ExtensionNotificationCategories.register(shown.buttons, in: center)
                if let image = shown.image, let attachment = ExtensionNotificationCategories.attachment(
                    image, type: shown.imageType
                ) {
                    content.attachments = [attachment]
                }
                let request = UNNotificationRequest(identifier: shown.identifier, content: content, trigger: nil)
                try? await center.add(request)
            },
            remove: { identifiers in
                guard !TestHost.isActive else { return }
                let center = UNUserNotificationCenter.current()
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            },
            isAllowed: {
                guard !TestHost.isActive else { return true }
                return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .denied
            }
        )
    }
}

/// The macOS categories of extension notifications: one per set of button
/// titles, each telling Ombre when it is dismissed.
@MainActor
enum ExtensionNotificationCategories {
    static let prefix = "ombre.extension.buttons:"
    nonisolated static let buttonPrefix = "button"
    private static var registered: [String: UNNotificationCategory] = [:]
    /// The most recent first: a few sets of buttons are kept, not all.
    private static var recent: [String] = []
    private static let maxCategories = 20

    static func identifier(for buttons: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: buttons)) ?? Data()
        return prefix + data.base64EncodedString()
    }

    static func register(_ buttons: [String], in center: UNUserNotificationCenter) async {
        let identifier = identifier(for: buttons)
        recent.removeAll { $0 == identifier }
        recent.insert(identifier, at: 0)
        guard registered[identifier] == nil else { return }
        let actions = buttons.enumerated().map { index, title in
            UNNotificationAction(identifier: buttonPrefix + String(index), title: title, options: [])
        }
        registered[identifier] = UNNotificationCategory(
            identifier: identifier, actions: actions, intentIdentifiers: [], options: [.customDismissAction]
        )
        for old in recent.dropFirst(maxCategories) {
            registered[old] = nil
        }
        recent = Array(recent.prefix(maxCategories))
        let ours = Set(registered.values)
        // Ombre's others stay as they are.
        let existing = await center.notificationCategories()
        center.setNotificationCategories(existing.filter { !$0.identifier.hasPrefix(prefix) }.union(ours))
    }

    /// The extension's picture, from a file macOS moves into its own store.
    static func attachment(_ data: Data, type: String?) -> UNNotificationAttachment? {
        let ext = switch type {
        case "image/jpeg": "jpg"
        case "image/gif": "gif"
        default: "png"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ombre-extension-notification-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "image", url: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            logger.notice("Extension notification picture not shown: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
