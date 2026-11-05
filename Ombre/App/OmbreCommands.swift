import SwiftUI

struct OmbreCommands: Commands {
    @AppStorage("AppAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(SidebarPosition.defaultsKey) private var sidebarPosition: SidebarPosition = .primary
    @AppStorage("ui.toolbar.hidden") private var isToolbarHidden: Bool = false
    @AppStorage("ui.toolbar.showfullurl") private var showFullURL: Bool = false
    @Environment(\.openWindow) private var openWindow
    /// Customized shortcuts show in the menus at once.
    @ObservedObject private var shortcuts = CustomKeyboardShortcutManager.shared

    var body: some Commands {
        // The system's File › Close (⌘W too) goes: ⌘W is "Close Tab" only,
        // and closes any other window itself (see `CloseCommand`).
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "normal") }
                .keyboardShortcut(KeyboardShortcuts.Window.new.keyboardShortcut)

            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut(KeyboardShortcuts.Window.newPrivate.keyboardShortcut)

            Button("New Tab") {
                NotificationCenter.default.post(name: .showLauncher, object: NSApp.keyWindow)
            }.keyboardShortcut(KeyboardShortcuts.Tabs.new.keyboardShortcut)

            Divider()

            ImportDataButton()

            Divider()

            Button("Close Tab") {
                CloseCommand.closeTab()
            }.keyboardShortcut(KeyboardShortcuts.Tabs.close.keyboardShortcut)

            Button("Close Window") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut(KeyboardShortcuts.Window.close.keyboardShortcut)
        }

        CommandGroup(after: .undoRedo) {
            Button("Find in Page") {
                NotificationCenter.default.post(name: .findInPage, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Edit.find.keyboardShortcut)

            Button("Find Next") {
                NotificationCenter.default.post(name: .findNext, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Edit.findNext.keyboardShortcut)

            Button("Find Previous") {
                NotificationCenter.default.post(name: .findPrevious, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Edit.findPrevious.keyboardShortcut)

            Divider()

            Button("Copy URL") {
                NotificationCenter.default.post(name: .copyAddressURL, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Address.copyURL.keyboardShortcut)
        }

        CommandGroup(replacing: .sidebar) {
            // APPEARANCE
            Picker("Appearance", selection: Binding(
                get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
                set: { newValue in
                    appearanceRaw = newValue.rawValue
                    NotificationCenter.default.post(
                        name: .setAppearance,
                        object: NSApp.keyWindow,
                        userInfo: ["appearance": newValue.rawValue]
                    )
                }
            )) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }

            Divider()

            // VISIBILITY
            Button("Zoom In") {
                NotificationCenter.default.post(name: .zoomPage, object: NSApp.keyWindow, userInfo: ["step": 1])
            }
            .keyboardShortcut(KeyboardShortcuts.Zoom.zoomIn.keyboardShortcut)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .zoomPage, object: NSApp.keyWindow, userInfo: ["step": -1])
            }
            .keyboardShortcut(KeyboardShortcuts.Zoom.zoomOut.keyboardShortcut)

            Button("Actual Size") {
                NotificationCenter.default.post(name: .zoomPage, object: NSApp.keyWindow, userInfo: ["step": 0])
            }
            .keyboardShortcut(KeyboardShortcuts.Zoom.reset.keyboardShortcut)

            Divider()

            Button("Translate Page…") {
                NotificationCenter.default.post(name: .translatePage, object: NSApp.keyWindow)
            }

            Divider()

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.App.toggleSidebar.keyboardShortcut)

            Button(isToolbarHidden ? "Show Toolbar" : "Hide Toolbar") {
                NotificationCenter.default.post(name: .toggleToolbar, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.App.toggleToolbar.keyboardShortcut)

            Divider()

            // LAYOUT
            Button(sidebarPosition == .primary ? "Right Side Tabs" : "Left Side Tabs") {
                NotificationCenter.default.post(name: .toggleSidebarPosition, object: NSApp.keyWindow)
            }

            Button(showFullURL ? "Hide Full URL" : "Show Full URL") {
                NotificationCenter.default.post(name: .toggleFullURL, object: NSApp.keyWindow)
            }
            Divider()
        }

        CommandMenu("Navigation") {
            Button("Reload Page") {
                NotificationCenter.default.post(name: .reloadPage, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.reload.keyboardShortcut)

            Button("Clear Cache & Reload") {
                NotificationCenter.default.post(name: .clearCacheAndReload, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.hardReload.keyboardShortcut)

            Button("Clear Cookies & Reload") {
                NotificationCenter.default.post(name: .clearCookiesAndReload, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.clearCookiesAndReload.keyboardShortcut)

            Divider()

            Button("Back") {
                NotificationCenter.default.post(name: .goBack, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.back.keyboardShortcut)

            Button("Forward") {
                NotificationCenter.default.post(name: .goForward, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.forward.keyboardShortcut)

            Divider()

            Button("Show History") {
                NotificationCenter.default.post(name: .showHistory, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.History.show.keyboardShortcut)

            Button("Show Browsing Time") {
                NotificationCenter.default.post(name: .showTime, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.History.time.keyboardShortcut)

            Button("Show Notes") {
                NotificationCenter.default.post(name: .showNotes, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Notes.show.keyboardShortcut)

            Button("Show Tasks") {
                NotificationCenter.default.post(name: .showTasks, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Notes.tasks.keyboardShortcut)

            #if DEBUG
                Divider()

                Button("Copy Page Crash Command (All Tabs in Space)") {
                    NotificationCenter.default.post(name: .simulatePageCrash, object: NSApp.keyWindow)
                }
            #endif
        }

        #if DEBUG
            CommandMenu("Debug") {
                Button("Show Onboarding Again") { openWindow(id: "onboarding") }
            }
        #endif

        CommandMenu("Tabs") {
            Button("Open Peek in New Tab") {
                NotificationCenter.default.post(name: .openPeekInTab, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Navigation.openPeekInNewTab.keyboardShortcut)

            Button("New Split View") {
                NotificationCenter.default.post(name: .newSplitView, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Tabs.newSplit.keyboardShortcut)

            Button("Reopen Closed Tab") {
                NotificationCenter.default.post(name: .restoreLastTab, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Tabs.restore.keyboardShortcut)

            Divider()

            Button("Pin Tab") {
                NotificationCenter.default.post(name: .togglePinTab, object: NSApp.keyWindow)
            }.keyboardShortcut(KeyboardShortcuts.Tabs.pin.keyboardShortcut)

            Divider()

            Button("Next Tab") {
                NotificationCenter.default.post(name: .nextTab, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Tabs.next.keyboardShortcut)

            Button("Previous Tab") {
                NotificationCenter.default.post(name: .previousTab, object: NSApp.keyWindow)
            }
            .keyboardShortcut(KeyboardShortcuts.Tabs.previous.keyboardShortcut)

            Divider()

            // Quick Tab Selection (1–9)
            ForEach(1 ... 9, id: \.self) { index in
                Button("Tab \(index)") {
                    NotificationCenter.default.post(
                        name: .selectTabAtIndex,
                        object: NSApp.keyWindow,
                        userInfo: ["index": index]
                    )
                }
                .keyboardShortcut(KeyboardShortcuts.Tabs.keyboardShortcut(for: index))
            }
        }

        CommandMenu("Passwords") {
            Button("Manage Passwords") {
                openPasswordsWindow()
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Ombre") {
                NSApp.orderFrontStandardAboutPanel(nil)
                NSApp.activate()
            }
            Button("Licenses") { openWindow(id: "licenses") }
            if UpdateService.isAvailable {
                Button("Check for Updates") {
                    UpdateService.shared.checkForUpdates()
                }
            }
        }

        CommandGroup(replacing: .appSettings) {
            // In the browser window, like the rest; the settings window
            // from a private window or another window.
            Button("Settings...") {
                if BrowserWindows.isNormal(NSApp.keyWindow) {
                    NotificationCenter.default.post(name: .showSettings, object: NSApp.keyWindow)
                } else {
                    openWindow(id: "settings")
                }
            }
            .keyboardShortcut(KeyboardShortcuts.App.preferences.keyboardShortcut)
        }
    }
}
