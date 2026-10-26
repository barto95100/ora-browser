import AppKit
import SwiftUI

final class TabBrowserPageDelegate: BrowserPageDelegate {
    weak var tab: Tab?
    weak var mediaController: MediaController?
    weak var passwordCoordinator: PasswordAutofillCoordinator?

    private var progressResetWorkItem: DispatchWorkItem?

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        guard navigationAction.modifierFlags.contains(.command),
              let url = navigationAction.request.url,
              let tab,
              let tabManager = tab.tabManager,
              let historyManager = tab.historyManager,
              let downloadManager = tab.downloadManager
        else {
            return .allow
        }

        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: tab.isPrivate
            )
        }
        return .openInNewTab
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL) {
        guard let tab,
              let tabManager = tab.tabManager,
              let historyManager = tab.historyManager
        else {
            return
        }

        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: historyManager,
                downloadManager: tab.downloadManager,
                isPrivate: tab.isPrivate
            )
        }
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        guard let tab else { return }

        switch event.phase {
        case .started:
            progressResetWorkItem?.cancel()
            // A prompt belongs to the page that asked; leaving it denies.
            tab.cancelPermissionRequest()
            tab.clearNavigationError()
            tab.crashRecoveryNavigationDidStart()
            tab.maintainSnapShots()
            passwordCoordinator?.clearAutofillState()
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
            if let url = event.url {
                tab.updateURL(url)
            }

        case .committed:
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
            if let title = event.title, !title.isEmpty {
                tab.title = title
                MainActor.assumeIsolated {
                    mediaController?.syncTitleForTab(tab.id, newTitle: title)
                }
            }

        case .finished:
            tab.crashRecoveryNavigationDidFinish()
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
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
            }

            let workItem = DispatchWorkItem { [weak tab] in
                tab?.loadingProgress = 0
            }
            progressResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        }
    }

    func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState) {
        tab?.updateMediaCaptureState(state)
    }

    func browserPageWebContentProcessDidTerminate(_ page: BrowserPage) {
        guard let tab else { return }

        progressResetWorkItem?.cancel()
        MainActor.assumeIsolated {
            // The media (and Picture in Picture) of the dead page is gone.
            mediaController?.removeSession(for: tab.id)
            tab.handleWebContentProcessTermination()
        }
    }

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {
        guard let tab, let url, tab.url != url else { return }

        tab.updateURL(url)
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
            // Avoid publishing an identical value, which would needlessly
            // invalidate the views observing the tab.
            if tab.hoveredLinkURL != newValue {
                tab.hoveredLinkURL = newValue
            }
        case "mediaEvent":
            handleMediaEventMessage(message.body, for: tab)
        case "favicon":
            if let json = message.body as? String,
               let favicon = try? JSONDecoder().decode(PageFaviconMessage.self, from: Data(json.utf8))
            {
                MainActor.assumeIsolated {
                    tab.updateFavicon(from: favicon)
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

        let types = permission.sitePermissionTypes
        let saved = SitePermissionStore.shared.permissions(
            for: origin,
            in: tab.container.id,
            isPrivate: tab.isPrivate
        )

        switch saved.decision(for: types) {
        case .allow:
            decisionHandler(.grant)
        case .deny:
            decisionHandler(.deny)
        case .ask:
            let request = SitePermissionRequest(origin: origin, types: types) { granted in
                decisionHandler(granted ? .grant : .deny)
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

    func browserPage(_ page: BrowserPage, runJavaScriptAlert message: String) {
        let alert = NSAlert()
        alert.messageText = "Alert"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func browserPage(_ page: BrowserPage, runJavaScriptConfirm message: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Confirm"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completion(alert.runModal() == .alertFirstButtonReturn)
    }

    func browserPage(
        _ page: BrowserPage,
        runJavaScriptPrompt prompt: String,
        defaultText: String?,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Prompt"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            completion(textField.stringValue)
        } else {
            completion(nil)
        }
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
                self.tab?.colorUpdated = true
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
