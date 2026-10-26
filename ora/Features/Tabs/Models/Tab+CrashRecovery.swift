import Foundation

extension Tab {
    /// Whether this tab is the one shown in its window.
    @MainActor var isShownInWindow: Bool {
        tabManager?.activeTab?.id == id
    }

    /// The process rendering the page ended: the page is blank until reloaded.
    @MainActor func handleWebContentProcessTermination() {
        // Whatever the dead page was showing or asking for is gone.
        cancelPermissionRequest()
        passwordCoordinator?.clearAutofillState()
        if hoveredLinkURL != nil { hoveredLinkURL = nil }
        isLoading = false
        loadingProgress = 0
        isReloadingAfterCrash = false
        if showsCrashRecoveryNotice { showsCrashRecoveryNotice = false }
        if mediaCaptureState.isCapturing { mediaCaptureState = BrowserMediaCaptureState() }

        switch crashRecovery.processDidTerminate(isVisible: isShownInWindow) {
        case .reloadNow:
            reloadAfterCrash()
        case .reloadWhenShown:
            break
        case .showCrashPage:
            setNavigationError(PageCrashError(), for: url)
        }
    }

    /// Reloads a page left unloaded by a crash, now that its tab is shown.
    @MainActor func recoverFromCrashIfNeeded() {
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
