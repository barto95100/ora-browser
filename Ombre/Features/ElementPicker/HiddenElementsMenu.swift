import AppKit

/// The page menu's items (address bar, "…"): the element picker, and the
/// elements hidden on the site, each one to show again.
@MainActor
enum HiddenElementsMenu {
    static func addItems(for tab: Tab, to menu: NSMenu, window: NSWindow?) {
        menu.autoenablesItems = false
        let pick = ActionMenuItem(title: String(localized: "Hide or Capture an Element…")) {
            NotificationCenter.default.post(name: .pickElement, object: window)
        }
        let isWebPage = tab.url.scheme == "https" || tab.url.scheme == "http"
        pick.isEnabled = isWebPage
        menu.addItem(pick)

        guard !tab.isPrivate, let site = WebSite.registrableDomain(of: tab.url) else { return }
        let spaceID = tab.container.id
        let elements = HiddenElementsStore.shared.elements(onSite: site, in: spaceID)
        let item = NSMenuItem(
            title: String(localized: "Hidden Elements on \(site) (\(elements.count))"),
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = !elements.isEmpty
        let submenu = NSMenu()
        for element in elements {
            let show = ActionMenuItem(title: String(localized: "Show Again: \(element.label)")) {
                ElementPicker.show(element.selector, onSite: site, in: spaceID, reloading: tab)
            }
            show.toolTip = element.selector
            submenu.addItem(show)
        }
        if !elements.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(ActionMenuItem(title: String(localized: "Show All on This Site")) {
                ElementPicker.show(nil, onSite: site, in: spaceID, reloading: tab)
            })
        }
        item.submenu = submenu
        menu.addItem(item)
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented") // not shown
    }

    @objc private func run() {
        handler()
    }
}
