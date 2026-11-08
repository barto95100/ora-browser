import Foundation
@preconcurrency import WebKit

/// Updates of the Chrome Web Store extensions, like Chrome: checked at launch
/// (once a day at most) and then daily, or on demand. An update that asks
/// for nothing more installs itself; one that asks for more waits for the
/// user (it can't grant itself new rights). Safari extensions are updated by
/// the App Store, and loaded again at the next launch.
@available(macOS 15.4, *)
extension WebExtensionsManager {
    struct PendingUpdate {
        let version: String
        let package: URL
        let webExtension: WKWebExtension
        /// What it asks for on top of what was allowed.
        let newPermissions: [String]
        let newSites: [String]
    }

    private static let lastCheckKey = "extensions.lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// A check soon after launch if the last one is a day old, then one a
    /// day: a single timer, nothing more.
    func scheduleUpdateChecks() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > Self.checkInterval {
            Task {
                try? await Task.sleep(for: .seconds(30))
                await checkForUpdates()
            }
        }
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in await WebExtensionsManager.shared.checkForUpdates() }
        }
        updateTimer?.tolerance = 60 * 60
    }

    /// The line under "Check for Updates": read from what is installed now,
    /// so a check's result never outlives the extensions it was about.
    var updateSummary: String {
        Self.updateSummary(
            status: updateStatus,
            hasStoreExtensions: installed.contains { $0.record.storeID != nil }
        )
    }

    nonisolated static func updateSummary(status: String?, hasStoreExtensions: Bool) -> String {
        guard hasStoreExtensions else { return "No extension from the Chrome Web Store." }
        return status ?? "Updates are checked once a day, like Chrome: the Chrome Web Store (Google) "
            + "receives the list of these extensions and their versions."
    }

    /// Forgets a check's result once the store extensions change, but not an
    /// update still waiting for review.
    func resetUpdateStatus() {
        updateStatus = pendingUpdates.isEmpty ? nil : "An update needs your review."
    }

    /// `reinstall` (Debug, ⌥-click): asks as if every version were 0, to
    /// test a whole update with the current versions.
    func checkForUpdates(reinstall: Bool = false) async {
        guard !isCheckingUpdates else { return }
        let extensions = installed.compactMap { item -> (storeID: String, version: String)? in
            guard let storeID = item.record.storeID else { return nil }
            let version = item.context?.webExtension.version ?? item.record.version ?? "0"
            return (storeID: storeID, version: reinstall ? "0" : version)
        }
        guard !extensions.isEmpty, let url = ChromeWebStoreUpdates.checkURL(for: extensions) else {
            // Nothing to check: the settings say so from the list itself.
            updateStatus = nil
            return
        }
        isCheckingUpdates = true
        defer {
            isCheckingUpdates = false
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: Self.chromeRequest(url))
            let updates = ChromeWebStoreUpdates.parse(data)
            var updated: [String] = []
            for item in extensions {
                guard let update = updates[item.storeID],
                      ExtensionVersion.isNewer(update.version, than: item.version),
                      let record = installed.first(where: { $0.record.storeID == item.storeID })?.record
                else { continue }
                // A refused package (not signed, too large…) doesn't stop the others.
                do {
                    if try await prepare(update, for: record) { updated.append(record.name) }
                } catch {
                    logger.error("Extension update refused: \(error.localizedDescription, privacy: .public)")
                }
            }
            let waiting = pendingUpdates.count
            updateStatus = switch (updated.isEmpty, waiting) {
            case (true, 0): "Everything is up to date."
            case (false, 0): "Updated: \(updated.joined(separator: ", "))."
            case (true, _): "An update needs your review."
            case (false, _): "Updated: \(updated.joined(separator: ", ")). An update needs your review."
            }
        } catch {
            logger.error("Extension update check failed: \(error.localizedDescription, privacy: .public)")
            updateStatus = "Couldn't check for updates."
        }
    }

    /// Downloads an update; installs it if it asks for nothing more (true),
    /// else keeps it for review.
    private func prepare(_ update: ChromeWebStoreUpdates.Update, for record: ExtensionRecord) async throws -> Bool {
        guard let storeID = record.storeID else { throw PackageFailure.download }
        let data = try await ChromeWebStore.downloadPackage(Self.chromeRequest(update.downloadURL))
        // The same extension, signed by its developer: never another one.
        let zip = try CRXVerifier.verifiedZip(from: data, extensionID: storeID)
        let package = try ExtensionPackages.store(zip: zip, id: "\(record.id).update")
        let webExtension = try await WKWebExtension(resourceBaseURL: package)

        let newPermissions = webExtension.requestedPermissions.map(\.rawValue)
            .filter { !record.grantedPermissions.contains($0) }.sorted()
        let allowed = Set(record.grantedMatchPatterns + record.extraMatchPatterns)
        let newSites = webExtension.allRequestedMatchPatterns.map(\.string)
            .filter { !allowed.contains($0) }.sorted()

        let pending = PendingUpdate(
            version: update.version, package: package, webExtension: webExtension,
            newPermissions: newPermissions, newSites: newSites
        )
        guard newPermissions.isEmpty, newSites.isEmpty else {
            pendingUpdates[record.id] = pending
            return false
        }
        try install(pending, id: record.id)
        return true
    }

    /// Accepts a reviewed update: what it asks for is allowed, then it runs.
    func acceptUpdate(id: String) {
        guard let pending = pendingUpdates.removeValue(forKey: id) else { return }
        // Allowed first: the new version loads with it.
        updateRecord(id: id) { record in
            record.grant(pending.newPermissions)
            record.grantedMatchPatterns = Array(Set(record.grantedMatchPatterns).union(pending.newSites)).sorted()
        }
        do {
            try install(pending, id: id)
        } catch {
            logger.error("Extension update not installed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Not now: the update is dropped, and offered again at the next check.
    func declineUpdate(id: String) {
        guard let pending = pendingUpdates.removeValue(forKey: id) else { return }
        ExtensionPackages.remove(path: pending.package.path)
    }

    /// The update's package takes the place of the current one, and the
    /// extension runs the new version.
    private func install(_ pending: PendingUpdate, id: String) throws {
        guard let record = installed.first(where: { $0.id == id })?.record else { return }
        let current = URL(fileURLWithPath: record.path)
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: pending.package)
        } catch {
            // Not left on the disk: the next check downloads it again.
            ExtensionPackages.remove(path: pending.package.path)
            throw error
        }
        Task {
            // Read again from its place: the downloaded copy has moved.
            do {
                let updated = try await WKWebExtension(resourceBaseURL: current)
                replaceRunning(id: id, with: updated)
            } catch {
                logger.error("Extension update not loaded: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A request as Chrome sends it (the Chrome Web Store serves Chrome).
    static func chromeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/\(ChromeWebStore.chromeVersion) Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }
}
