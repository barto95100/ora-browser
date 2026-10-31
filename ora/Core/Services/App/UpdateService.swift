import os.log
import Sparkle
import SwiftUI

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "UpdateService")

class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    /// Whether this build can update itself: it needs both its own appcast
    /// (`SUFeedURL`) and the public key that signs its updates (`SUPublicEDKey`).
    /// Without them, no Sparkle updater is created and the update controls are hidden.
    static let isAvailable = updatesConfigured(in: Bundle.main.infoDictionary)

    @Published var canCheckForUpdates = false
    @Published var updateProgress: Double = 0.0
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var lastCheckResult: String?
    @Published var lastCheckDate: Date?

    private var updater: SPUUpdater?
    private var userDriver: SPUStandardUserDriver?

    /// Sparkle supports a single updater per bundle: use `shared`.
    override private init() {
        super.init()
        guard Self.isAvailable else {
            logger.info("Updates unavailable: no SUFeedURL or SUPublicEDKey in Info.plist")
            return
        }
        setupUpdater()
    }

    static func updatesConfigured(in info: [String: Any]?) -> Bool {
        func hasValue(_ key: String) -> Bool {
            guard let value = info?[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasValue("SUFeedURL") && hasValue("SUPublicEDKey")
    }

    private func setupUpdater() {
        let hostBundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        let updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: self
        )

        self.updater = updater
        self.userDriver = userDriver

        do {
            try updater.start()
            canCheckForUpdates = true
        } catch {
            logger.error("❌ Failed to start updater - Error: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        guard Self.isAvailable else { return }
        guard let updater, canCheckForUpdates else {
            logger
                .error(
                    "❌ Update checking not available - updater: \(self.updater != nil), canCheck: \(self.canCheckForUpdates)"
                )
            lastCheckResult = "Update checking is not available"
            lastCheckDate = Date()
            isCheckingForUpdates = false
            return
        }

        isCheckingForUpdates = true
        lastCheckResult = "Checking for updates..."
        lastCheckDate = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.isCheckingForUpdates == true {
                self?.isCheckingForUpdates = false
                self?.lastCheckResult = "Update check timed out"
                self?.lastCheckDate = Date()
            }
        }

        updater.checkForUpdates()
    }

    func checkForUpdatesInBackground() {
        guard let updater, canCheckForUpdates else { return }
        updater.checkForUpdatesInBackground()
    }
}

extension UpdateService: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString

        DispatchQueue.main.async {
            self.updateAvailable = true
            self.isCheckingForUpdates = false
            self.lastCheckResult = "Update available: \(version)"
            self.lastCheckDate = Date()
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        logger.error("❌ Error details: \(error.localizedDescription)")
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        DispatchQueue.main.async {
            self.updateAvailable = false
            self.isCheckingForUpdates = false
            self.lastCheckResult = "No updates available (current: \(currentVersion))"
            self.lastCheckDate = Date()
        }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        DispatchQueue.main.async {
            self.updateProgress = 0.0
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.updateProgress = 1.0
        }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        // Update extracted, ready for installation
    }

    func updater(_ updater: SPUUpdater, failedToLoadAppcastWithError error: Error) {
        logger.error("❌ Error: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isCheckingForUpdates = false
            self.lastCheckResult = "Failed to load appcast: \(error.localizedDescription)"
            self.lastCheckDate = Date()
        }
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        logger.error("❌ Error: \(error.localizedDescription)")
        let version = item.displayVersionString
        logger.error("❌ Item version: \(version)")

        DispatchQueue.main.async {
            self.isCheckingForUpdates = false
            self.lastCheckResult = "Download failed: \(error.localizedDescription)"
            self.lastCheckDate = Date()
        }
    }
}
