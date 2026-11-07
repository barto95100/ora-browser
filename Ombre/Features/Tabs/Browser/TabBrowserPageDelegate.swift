import AppKit
@preconcurrency import WebKit
import SwiftUI

final class TabBrowserPageDelegate: BrowserPageDelegate {
    weak var tab: Tab?
    /// When the page may show `alert`, `confirm` and `prompt` dialogs.
    var dialogPolicy = JavaScriptDialogPolicy()
    /// The dialog sheet open for the page, and its window (see `dismissDialog`).
    weak var dialogSheet: NSWindow?
    weak var dialogParentWindow: NSWindow?
    weak var mediaController: MediaController?
    weak var passwordCoordinator: PasswordAutofillCoordinator?

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        // Links from pinned and favorite tabs to other sites: Peek (like Arc)
        // or a new tab, as set in General settings.
        let pinnedLinkBehavior = SettingsStore.shared.pinnedLinkBehavior
        if let tab, let url = navigationAction.request.url,
           PeekPolicy.opensInPeek(
               tabType: tab.type,
               isLinkClick: navigationAction.isMainFrameLinkClick,
               modifierFlags: navigationAction.modifierFlags,
               from: tab.url,
               to: url,
               isEnabled: pinnedLinkBehavior != .sameTab
           )
        {
            if pinnedLinkBehavior == .peek {
                tab.openPeek(url)
            } else if let tabManager = tab.tabManager {
                MainActor.assumeIsolated {
                    _ = tabManager.openLinkTab(url, from: tab, disposition: .foreground)
                }
            }
            return .cancel
        }

        guard navigationAction.modifierFlags.contains(.command),
              let url = navigationAction.request.url,
              let tab,
              let tabManager = tab.tabManager
        else {
            return .allow
        }

        // ⌘-click opens the link in a background tab, ⌘⇧-click in front, like
        // Safari. The tab is opened here, so the navigation is just cancelled
        // (`.openInNewTab` would have the page open it a second time).
        let inFront = navigationAction.modifierFlags.contains(.shift)
        MainActor.assumeIsolated {
            _ = tabManager.openLinkTab(url, from: tab, disposition: inFront ? .foreground : .background)
        }
        return .cancel
    }

    /// A `target="_blank"` link clicked in a pinned or favorite tab, to
    /// another site: Peek when the setting asks for it, like a plain link.
    func browserPage(_ page: BrowserPage, opensNewWindowLink url: URL, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let tab, SettingsStore.shared.pinnedLinkBehavior == .peek,
              PeekPolicy.opensInPeek(
                  tabType: tab.type,
                  isLinkClick: true,
                  modifierFlags: modifierFlags,
                  from: tab.url,
                  to: url,
                  isEnabled: true
              )
        else { return false }
        tab.openPeek(url)
        return true
    }

    func browserPage(
        _ page: BrowserPage,
        linkedPageWith configuration: WKWebViewConfiguration,
        for url: URL?,
        disposition: BrowserNewTabDisposition
    ) -> WKWebView? {
        guard let tab, let tabManager = tab.tabManager else { return nil }
        return MainActor.assumeIsolated {
            tabManager.openLinkedTab(url: url, from: tab, configuration: configuration, disposition: disposition)
        }
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition) {
        guard let tab, let tabManager = tab.tabManager else { return }
        MainActor.assumeIsolated {
            _ = tabManager.openLinkTab(url, from: tab, disposition: disposition)
        }
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        guard let tab else { return }

        switch event.phase {
        case .started:
            // A prompt belongs to the page that asked; leaving it denies.
            tab.cancelPermissionRequest()
            tab.clearNavigationError()
            tab.crashRecoveryNavigationDidStart()
            if tab.folderAccessRequest != nil { tab.folderAccessRequest = nil }
            if !tab.blockedContent.isEmpty { tab.blockedContent = [:] }
            passwordCoordinator?.clearAutofillState()
            tab.isLoading = event.isLoading
            if let url = event.url {
                tab.updateURL(url)
            }
            WebExtensionsHub.tabChanged(tab, url: true, loading: true)

        case .committed:
            dialogPolicy.pageDidCommitNewDocument()
            // A new document: its language is checked once it has loaded.
            MainActor.assumeIsolated { tab.runtime?.resetTranslation() }
            tab.isLoading = event.isLoading
            if let title = event.title, !title.isEmpty {
                tab.title = title
            }
            // A new document replaced the page: its media (and Picture in
            // Picture) are gone, and the script sends no event on unload.
            // Same-document navigations (history API) don't commit.
            MainActor.assumeIsolated {
                mediaController?.removeSession(for: tab.id)
            }

        case .finished:
            tab.crashRecoveryNavigationDidFinish()
            tab.isLoading = event.isLoading
            if let title = event.title, !title.isEmpty {
                tab.title = title
                MainActor.assumeIsolated {
                    mediaController?.syncTitleForTab(tab.id, newTitle: title)
                }
            }
            if let url = event.url {
                tab.updateURL(url)
                tab.recordVisit()
                tab.updateHeaderColor()
                MainActor.assumeIsolated { tab.checkPageLanguage() }
                if url.isFileURL { tab.offerFolderAccessIfNeeded() }
            }
            WebExtensionsHub.tabChanged(tab, url: true, title: true, loading: true)
        }
    }

    func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState) {
        tab?.updateMediaCaptureState(state)
    }

    func browserPageWebContentProcessDidTerminate(_ page: BrowserPage) {
        guard let tab else { return }

        MainActor.assumeIsolated {
            // The media (and Picture in Picture) of the dead page is gone.
            mediaController?.removeSession(for: tab.id)
            tab.handleWebContentProcessTermination()
        }
    }

    func browserPageContextMenuItems(_ page: BrowserPage) -> [NSMenuItem] {
        guard let tab else { return [] }
        return MainActor.assumeIsolated { tab.translationMenuItems() }
    }

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {
        guard let tab, let url, tab.url != url else { return }

        tab.updateURL(url)
        WebExtensionsHub.tabChanged(tab, url: true)
        // Same-page navigations (history API, fragments) have no "finished"
        // event: record them here. Full loads are recorded when they finish.
        if !page.isLoading {
            tab.recordVisit()
        }
    }

    func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {
        guard let tab else { return }

        // Pages without a <title> report an empty one: show the host or the
        // file name instead (like Safari) rather than a blank tab.
        let newTitle: String
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newTitle = title
        } else if let fallback = MainActor.assumeIsolated({
            page.currentURL.flatMap { TabManager.initialTitleAndFavicon(for: $0)?.title }
        }) {
            newTitle = fallback
        } else {
            return
        }
        guard tab.title != newTitle else { return }

        tab.title = newTitle
        tab.updateHistoryTitle()
        WebExtensionsHub.tabChanged(tab, title: true)
        MainActor.assumeIsolated {
            mediaController?.syncTitleForTab(tab.id, newTitle: newTitle)
        }
    }

    func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?) {
        tab?.setNavigationError(error, for: failingURL)
    }

    func browserPage(_ page: BrowserPage, didReceiveScriptMessage message: BrowserScriptMessage) {
        guard let tab else { return }

        switch message.name {
        case "linkHover":
            let hovered = (message.body as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue: String? = hovered.isEmpty ? nil : hovered
            MainActor.assumeIsolated { tab.runtime?.setHoveredLink(newValue) }
        case "mediaEvent":
            handleMediaEventMessage(message.body, for: tab)
        case "favicon":
            if let json = message.body as? String,
               let favicon = try? JSONDecoder().decode(PageFaviconMessage.self, from: Data(json.utf8))
            {
                MainActor.assumeIsolated {
                    tab.updateFavicon(from: favicon, pageURL: page.currentURL)
                }
            }
        case "passwordManager":
            if let body = message.body as? String {
                passwordCoordinator?.handleMessage(body, pageURL: page.currentURL)
            }
        default:
            break
        }
    }

    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        guard let tab, let origin = origin.flatMap(SiteOrigin.init(url:)) else {
            decisionHandler(.deny)
            return
        }
        // A site allowed to send notifications: macOS must allow Ombre too
        // (asked once, right after the user allowed the site).
        let answer: (BrowserPermissionDecision) -> Void = switch permission {
        case .notifications: { decision in
                if decision == .grant {
                    WebNotificationCenter.shared.requestAuthorizationIfNeeded()
                }
                decisionHandler(decision)
            }
        // A site allowed to know the position: macOS must let Ombre use
        // Location Services too (WebKit never asks it).
        case .geolocation: LocationAuthorization.askingMacOS(then: decisionHandler)
        default: decisionHandler
        }

        let types = permission.sitePermissionTypes
        let saved = SitePermissionStore.shared.permissions(
            for: origin,
            in: tab.container.id,
            isPrivate: tab.isPrivate
        )

        switch saved.decision(for: types) {
        case .allow:
            answer(.grant)
        case .deny:
            answer(.deny)
        case .ask:
            let request = SitePermissionRequest(origin: origin, types: types) { granted in
                answer(granted ? .grant : .deny)
            }
            tab.presentPermissionRequest(request)
        }
    }

    func browserPage(
        _ page: BrowserPage,
        queryPermission permission: BrowserPermissionKind,
        origin: URL?
    ) -> BrowserPermissionDecision {
        guard let tab, let origin = origin.flatMap(SiteOrigin.init(url:)) else {
            return .prompt
        }

        return SitePermissionStore.shared
            .permissions(for: origin, in: tab.container.id, isPrivate: tab.isPrivate)
            .decision(for: permission.sitePermissionTypes)
            .permissionQueryDecision
    }

    func browserPage(
        _ page: BrowserPage,
        runOpenPanelWith options: BrowserOpenPanelOptions,
        completion: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = options.allowsDirectories
        openPanel.allowsMultipleSelection = options.allowsMultipleSelection
        openPanel.begin { result in
            completion(result == .OK ? openPanel.urls : nil)
        }
    }

    func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool {
        guard let tab else { return true }
        return tab.areProtectionsEnabled(for: url)
    }

    func browserPage(_ page: BrowserPage, didBlockContentFrom url: URL) {
        tab?.recordBlockedContent(from: url)
    }

    /// In spaces that block trackers, except for exempted sites.
    func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool {
        guard let tab else { return false }
        return tab.privacySettings.blockThirdPartyTrackers && tab.areProtectionsEnabled(for: url)
    }

    func browserPage(_ page: BrowserPage, showNotification notification: BrowserWebNotification) {
        guard let tab else { return }
        WebNotificationCenter.shared.show(notification, from: tab)
    }

    func browserPage(_ page: BrowserPage, closeNotification id: String) {
        guard let tab else { return }
        WebNotificationCenter.shared.close(id, from: tab)
    }

    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {
        MainActor.assumeIsolated {
            tab?.downloadManager?.handleDownload(download)

            guard page.isDownloadNavigation, let tab else { return }

            if page.lastCommittedURL != nil {
                tab.goBack()
            } else if let tabManager = tab.tabManager {
                tabManager.closeTab(tab: tab)
            }
        }
    }

    func browserPage(_ page: BrowserPage, didChangeThemeColor color: NSColor?) {
        guard let tab else { return }
        if let color {
            tab.updateBackgroundColor(Color(nsColor: color))
        } else if !page.isLoading {
            // It no longer declares one: read its top again (after a load,
            // `.finished` does).
            tab.updateHeaderColor()
        }
    }

    func takeSnapshotAfterLoad(_ page: BrowserPage) {
        guard !page.isLoading, page.contentView.bounds.width > 0 else { return }

        page.takeSnapshot(
            configuration: BrowserSnapshotConfiguration(
                rect: CGRect(x: 0, y: 0, width: page.contentView.bounds.width, height: 24),
                afterScreenUpdates: false
            )
        ) { [weak self] image, error in
            guard let self, let image, error == nil else { return }
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let color = self.extractDominantColor(from: cgImage) ?? .black
            DispatchQueue.main.async {
                self.tab?.updateBackgroundColor(Color(nsColor: color))
            }
        }
    }

    private func handleMediaEventMessage(_ body: Any?, for tab: Tab) {
        guard let payloadBody = body as? String,
              let data = payloadBody.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MediaEventPayload.self, from: data)
        else {
            return
        }

        MainActor.assumeIsolated {
            mediaController?.receive(event: payload, from: tab)
        }
    }

    private func extractDominantColor(from cgImage: CGImage) -> NSColor? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return nil }

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        return NSColor(
            red: CGFloat(pixels[0]) / 255.0,
            green: CGFloat(pixels[1]) / 255.0,
            blue: CGFloat(pixels[2]) / 255.0,
            alpha: CGFloat(pixels[3]) / 255.0
        )
    }
}
