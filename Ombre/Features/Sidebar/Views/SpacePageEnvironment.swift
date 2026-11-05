import SwiftData
import SwiftUI

/// What a space's page in the sidebar reads from its window's environment,
/// given to it again. The pages are hosted apart (`NSPageView`): a page made
/// while the app runs (a new space shown at once) is first laid out alone,
/// with none of the window's environment, and a missing object crashes it.
/// Keep in step with what `ContainerView` and its views read (a test hosts it
/// with only these). Values that aren't there yet when the page is made, or
/// that change while it lives (the window, the space's theme), come from the
/// window once the page joins it.
struct SpacePageEnvironment: ViewModifier {
    let appState: AppState
    let downloadManager: DownloadManager
    let historyManager: HistoryManager
    let privacyMode: PrivacyMode
    let sidebarManager: SidebarManager
    let tabManager: TabManager
    let toastManager: ToastManager
    let toolbarManager: ToolbarManager
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .environmentObject(appState)
            .environmentObject(downloadManager)
            .environmentObject(historyManager)
            .environmentObject(privacyMode)
            .environmentObject(sidebarManager)
            .environmentObject(tabManager)
            .environmentObject(toastManager)
            .environmentObject(toolbarManager)
            .environment(\.modelContext, modelContext)
    }
}
