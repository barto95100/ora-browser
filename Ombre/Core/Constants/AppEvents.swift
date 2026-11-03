import Foundation

extension Notification.Name {
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let toggleSidebarPosition = Notification.Name("ToggleSidebarPosition")
    static let copyAddressURL = Notification.Name("CopyAddressURL")

    static let showLauncher = Notification.Name("ShowLauncher")
    static let showHistory = Notification.Name("ShowHistory")
    static let showNotes = Notification.Name("ShowNotes")
    static let showTasks = Notification.Name("ShowTasks")
    static let showTime = Notification.Name("ShowTime")
    static let showSettings = Notification.Name("ShowSettings")
    /// Import from another browser; the object is the browser window to import into.
    static let showImport = Notification.Name("ShowImport")
    /// Delete a space; `userInfo["spaceID"]` is the space, the object the window to do it.
    static let deleteSpace = Notification.Name("DeleteSpace")
    /// A task reminder clicked; `userInfo["spaceID"]` is the task's space.
    static let openTaskReminder = Notification.Name("OpenTaskReminder")
    static let closeActiveTab = Notification.Name("CloseActiveTab")
    static let openPeekInTab = Notification.Name("OpenPeekInTab")
    static let newSplitView = Notification.Name("NewSplitView")
    static let restoreLastTab = Notification.Name("RestoreLastTab")
    static let findInPage = Notification.Name("FindInPage")
    static let toggleFullURL = Notification.Name("ToggleFullURL")
    static let reloadPage = Notification.Name("ReloadPage")
    static let simulatePageCrash = Notification.Name("SimulatePageCrash") // Debug builds only
    static let goBack = Notification.Name("GoBack")
    static let goForward = Notification.Name("GoForward")
    static let togglePinTab = Notification.Name("TogglePinTab")
    static let nextTab = Notification.Name("NextTab")
    static let previousTab = Notification.Name("PreviousTab")
    static let toggleToolbar = Notification.Name("ToggleToolbar")
    static let selectTabAtIndex = Notification.Name("SelectTabAtIndex") // userInfo: ["index": Int]

    /// Per-window settings/events
    static let setAppearance = Notification.Name("SetAppearance") // userInfo: ["appearance": String]

    /// AppDelegate → UI routing
    static let openURL = Notification.Name("OpenURL") // userInfo: ["url": URL]

    // Cache and cookies
    static let clearCacheAndReload = Notification.Name("ClearCacheAndReload")
    static let clearCookiesAndReload = Notification.Name("ClearCookiesAndReload")
    static let spacePrivacySettingsChanged = Notification.Name("SpacePrivacySettingsChanged")

    /// App lifecycle
    static let quitRequested = Notification.Name("QuitRequested")
}
