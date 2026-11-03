//
//  DefaultBrowserManager.swift
//  Ombre
//
//  Created by keni on 9/30/25.
//

import AppKit

/// Tracks whether this app is the system default browser.
///
/// The status is checked at launch, whenever the app becomes active, when the settings appear and
/// after a "set as default" request — never on a timer.
@MainActor
final class DefaultBrowserManager: ObservableObject {
    typealias SetAsDefault = (_ completion: @escaping @Sendable () -> Void) -> Void

    static let shared = DefaultBrowserManager(
        defaultBrowserBundleID: DefaultBrowserManager.systemDefaultBrowserBundleID,
        ownBundleID: Bundle.main.bundleIdentifier,
        setAsDefault: DefaultBrowserManager.systemSetAsDefault
    )

    @Published private(set) var isDefault: Bool = false

    private let defaultBrowserBundleID: () -> String?
    private let ownBundleID: String?
    private let setAsDefault: SetAsDefault
    private let notificationCenter: NotificationCenter
    private var activationObserver: NSObjectProtocol?

    init(
        defaultBrowserBundleID: @escaping () -> String?,
        ownBundleID: String?,
        setAsDefault: @escaping SetAsDefault,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaultBrowserBundleID = defaultBrowserBundleID
        self.ownBundleID = ownBundleID
        self.setAsDefault = setAsDefault
        self.notificationCenter = notificationCenter
        refresh()
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Re-reads the default browser and publishes the status only when it changed.
    func refresh() {
        let newValue = Self.isDefault(defaultBrowserID: defaultBrowserBundleID(), ownBundleID: ownBundleID)
        if newValue != isDefault {
            isDefault = newValue
        }
    }

    /// Asks macOS to make this app the default browser, then refreshes the status
    /// whether the user accepted or declined.
    func requestSetAsDefault() {
        setAsDefault { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Bundle identifiers are case-insensitive for LaunchServices.
    nonisolated static func isDefault(defaultBrowserID: String?, ownBundleID: String?) -> Bool {
        guard let defaultBrowserID, let ownBundleID else { return false }
        return defaultBrowserID.caseInsensitiveCompare(ownBundleID) == .orderedSame
    }

    // MARK: - System (LaunchServices)

    private nonisolated static func systemDefaultBrowserBundleID() -> String? {
        guard let testURL = URL(string: "http://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: testURL)
        else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    private nonisolated static func systemSetAsDefault(completion: @escaping @Sendable () -> Void) {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { _ in
                completion()
            }
        }
    }
}
