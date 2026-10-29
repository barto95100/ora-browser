import SwiftUI

/// A tab's page with its overlays (prompts, find bar, link preview...), or its
/// error or loading state. Shown alone, or as one side of a split.
struct TabPageContent: View {
    @Environment(\.theme) var theme
    @EnvironmentObject private var appState: AppState
    let tab: Tab

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if tab.isWebViewReady {
            if tab.hasNavigationError, let error = tab.navigationError {
                StatusPageView(
                    error: error,
                    failedURL: tab.failedURL,
                    onRetry: { tab.retryNavigation() },
                    onGoBack: tab.canGoBack
                        ? {
                            tab.goBack()
                            tab.clearNavigationError()
                        } : nil,
                    onContinueAnyway: {
                        tab.continueToInsecureSite()
                    }
                )
                .id(tab.id)
            } else if let page = tab.browserPage {
                BrowserPageView(page: page).id(tab.id)
                    .overlay(alignment: .topLeading) {
                        if let triggerState = tab.passwordTriggerOverlayState {
                            PasswordAutofillTriggerView(overlay: triggerState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let passwordOverlayState = tab.passwordOverlayState {
                            PasswordAutofillOverlayView(overlay: passwordOverlayState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if appState.showFinderIn == tab.id {
                            FindView(page: page)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let hovered = tab.hoveredLinkURL, !hovered.isEmpty {
                            LinkPreview(text: hovered)
                        }
                    }
                    .overlay(alignment: .top) {
                        if let request = tab.permissionRequest {
                            SitePermissionPromptView(request: request, isPrivate: tab.isPrivate) { granted, remember in
                                tab.answerPermissionRequest(granted: granted, remember: remember)
                            }
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .top) {
                        if tab.showsCrashRecoveryNotice {
                            PageCrashNoticeView { tab.dismissCrashRecoveryNotice() }
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: tab.hoveredLinkURL)
                    .animation(.easeOut(duration: 0.2), value: tab.permissionRequest)
                    .overlay(alignment: .top) {
                        if let folder = tab.folderAccessRequest {
                            LocalFolderAccessPromptView(
                                folderName: folder.lastPathComponent,
                                onAllow: { tab.requestFolderAccess() },
                                onDismiss: { tab.folderAccessRequest = nil }
                            )
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: tab.showsCrashRecoveryNotice)
                    .animation(.easeOut(duration: 0.2), value: tab.folderAccessRequest)
                    // A site blocked during focus.
                    .overlay { FocusBlockView(tab: tab) }
            } else {
                ZStack {
                    Rectangle().fill(theme.background)
                    ProgressView().frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ZStack {
                Rectangle().fill(theme.background)
                ProgressView().frame(width: 32, height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
