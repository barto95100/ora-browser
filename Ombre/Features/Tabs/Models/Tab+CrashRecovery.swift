import Foundation

@MainActor
extension Tab {
    /// Whether this tab is the one shown in its window.
    var isShownInWindow: Bool {
        tabManager?.activeTab?.id == id
    }

    /// The process rendering the page ended: the page is blank until reloaded.
    func handleWebContentProcessTermination() {
        // Whatever the dead page was showing or asking for is gone.
        cancelPermissionRequest()
        passwordCoordinator?.clearAutofillState()
        runtime?.setHoveredLink(nil)
        isLoading = false
        isReloadingAfterCrash = false
        if showsCrashRecoveryNotice { showsCrashRecoveryNotice = false }
        if mediaCaptureState.isCapturing { mediaCaptureState = BrowserMediaCaptureState() }

        let action = crashRecovery.processDidTerminate(isVisible: isShownInWindow)
        browserPage?.log("process ended: \(action)")
        switch action {
        case .reloadNow:
            reloadAfterCrash()
        case .reloadWhenShown:
            break
        case .showCrashPage:
            setNavigationError(PageCrashError(), for: url)
        }
    }

    /// Reloads a page left unloaded by a crash, now that its tab is shown.
    func recoverFromCrashIfNeeded() {
        if crashRecovery.tabDidBecomeVisible() {
            reloadAfterCrash()
        }
    }

    func dismissCrashRecoveryNotice() {
        if showsCrashRecoveryNotice { showsCrashRecoveryNotice = false }
    }

    /// Called when a navigation starts: the notice explains the automatic reload
    /// only, so it goes away with the next page the user opens.
    func crashRecoveryNavigationDidStart() {
        if !isReloadingAfterCrash { dismissCrashRecoveryNotice() }
    }

    func crashRecoveryNavigationDidFinish() {
        isReloadingAfterCrash = false
    }

    private func reloadAfterCrash() {
        isReloadingAfterCrash = true
        showsCrashRecoveryNotice = true
        browserPage?.reload()
    }
}
