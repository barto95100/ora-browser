import AppKit
import SwiftUI
@preconcurrency import WebKit

/// The enabled extensions' buttons, right of the sidebar button (top of the
/// sidebar, or the address bar while the sidebar is hidden). Pinned ones as
/// many as fit; the others in the extensions menu. A click shows the
/// extension's popup under it; a right click, its menu.
/// Nothing in private windows, nor before macOS 15.4.
struct ExtensionStrip: View {
    let foregroundColor: Color
    /// At most this many buttons (in the address bar); nil: as many as fit
    /// in the space left (the strip then takes it all).
    var maxVisible: Int?
    @EnvironmentObject private var privacyMode: PrivacyMode

    var body: some View {
        if #available(macOS 15.4, *), !privacyMode.isPrivate {
            ExtensionStripContent(foregroundColor: foregroundColor, maxVisible: maxVisible)
        } else if maxVisible == nil {
            Spacer(minLength: 0)
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionStripContent: View {
    let foregroundColor: Color
    let maxVisible: Int?
    @ObservedObject private var manager = WebExtensionsManager.shared
    @EnvironmentObject private var tabManager: TabManager
    @State private var width: CGFloat = 0

    private static let slot: CGFloat = 30

    var body: some View {
        // Redrawn when an extension changes its icon, badge, state or access.
        let revision = manager.actionsRevision
        let items = manager.loadedContexts
        let pinned = items.filter(\.record.isPinned)
        let unpinned = items.filter { !$0.record.isPinned }
        let shown = ExtensionStripLayout.visibleCount(
            items: pinned.count,
            capacity: maxVisible ?? Int(width / Self.slot),
            hasMenu: !unpinned.isEmpty
        )
        HStack(spacing: 0) {
            ForEach(pinned.prefix(shown), id: \.record.id) { item in
                ExtensionActionButton(
                    record: item.record,
                    context: item.context,
                    tab: tabManager.activeTab,
                    foregroundColor: foregroundColor
                )
                .id("\(item.record.id)-\(revision)")
            }
            if shown < items.count {
                ExtensionOverflowMenu(
                    items: Array(pinned.dropFirst(shown)) + unpinned,
                    tab: tabManager.activeTab,
                    foregroundColor: foregroundColor
                )
            }
        }
        .frame(maxWidth: maxVisible == nil ? .infinity : nil, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if maxVisible == nil, newWidth != width { width = newWidth }
        }
    }
}

/// How many buttons show: all if they fit, else one less than fits, to
/// leave room for the menu of the others (always there with unpinned ones).
enum ExtensionStripLayout {
    static func visibleCount(items: Int, capacity: Int, hasMenu: Bool = false) -> Int {
        let capacity = max(capacity, 0)
        if hasMenu { return min(items, max(capacity - 1, 0)) }
        return items <= capacity ? items : max(capacity - 1, 0)
    }
}

@available(macOS 15.4, *)
private struct ExtensionActionButton: View {
    let record: ExtensionRecord
    let context: WKWebExtensionContext
    let tab: Tab?
    let foregroundColor: Color
    @State private var anchor = AnchorView()
    @State private var isHovering = false
    @State private var askingHost: String?

    private var manager: WebExtensionsManager {
        WebExtensionsManager.shared
    }

    var body: some View {
        let action = context.action(for: tab.map { manager.adapter(for: $0) })
        let hostAsking = manager.hostAskingAccess(context, tab: tab)
        Button {
            if let hostAsking {
                askingHost = hostAsking
            } else {
                manager.performAction(context, for: tab, anchor: anchor.view)
            }
        } label: {
            ExtensionIcon(action: action, foregroundColor: foregroundColor, wantsAccess: hostAsking != nil)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovering ? foregroundColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .background(AnchorReader(anchor: anchor, extensionID: record.id))
        .opacity(action?.isEnabled == false ? 0.4 : 1)
        .help(hostAsking.map { "\(record.name) wants to access \($0)" } ?? action?.label ?? record.name)
        .accessibilityLabel(Text(action?.label ?? record.name))
        .popover(isPresented: Binding(
            get: { askingHost != nil },
            set: { if !$0 { askingHost = nil } }
        ), arrowEdge: .bottom) {
            if let host = askingHost {
                ExtensionAccessPrompt(name: record.name, host: host) { decision, forOneDay in
                    manager.setSite(host, decision, forOneDay: forOneDay, id: record.id)
                    askingHost = nil
                    // Then what the click was for: its popup.
                    DispatchQueue.main.async {
                        manager.performAction(context, for: tab, anchor: anchor.view)
                    }
                }
            }
        }
        .contextMenu {
            ExtensionMenuItems(record: record, context: context, tab: tab)
        }
    }
}

/// An extension's menu (right click on its button): options, access to the
/// website, pin, settings, remove.
@available(macOS 15.4, *)
private struct ExtensionMenuItems: View {
    let record: ExtensionRecord
    let context: WKWebExtensionContext
    let tab: Tab?

    private var manager: WebExtensionsManager {
        WebExtensionsManager.shared
    }

    var body: some View {
        if context.optionsPageURL != nil {
            Button("Options…") { manager.openOptions(context) }
        }
        if let host = ExtensionSiteAccess.host(of: tab?.browserPage?.extensionWebView.url ?? tab?.url) {
            let current = ExtensionSiteAccess.decision(for: host, in: record)
            Menu("Access on \(host)") {
                choice("Allow", checked: current == .allow) { manager.setSite(host, .allow, id: record.id) }
                choice("Allow for One Day", checked: false) {
                    manager.setSite(host, .allow, forOneDay: true, id: record.id)
                }
                choice("Ask", checked: current == .ask) { manager.setSite(host, .ask, id: record.id) }
                choice("Don't Allow", checked: current == .deny) { manager.setSite(host, .deny, id: record.id) }
            }
        }
        Button(record.isPinned ? "Move to Extensions Menu" : "Pin Next to the Sidebar Button") {
            manager.setPinned(!record.isPinned, id: record.id)
        }
        Divider()
        Button("Manage Extension…") { BrowserWindows.showSettings(.extensions) }
        Button("Remove…", role: .destructive) { manager.confirmRemove(id: record.id) }
    }

    private func choice(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Asked on the first click on a website the extension wants (like Safari).
@available(macOS 15.4, *)
private struct ExtensionAccessPrompt: View {
    let name: String
    let host: String
    let choose: (_ decision: SiteDecision, _ forOneDay: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow “\(name)” on \(host)?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("It will be able to read and change this website's pages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                Button { choose(.allow, true) } label: { Text("Allow for One Day").frame(maxWidth: .infinity) }
                Button { choose(.allow, false) } label: {
                    Text("Always Allow on This Website").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                Button { choose(.deny, false) } label: { Text("Don't Allow").frame(maxWidth: .infinity) }
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 280)
    }
}

/// The extensions that don't fit or aren't pinned; the chosen one's popup
/// shows under it.
@available(macOS 15.4, *)
private struct ExtensionOverflowMenu: View {
    let items: [(record: ExtensionRecord, context: WKWebExtensionContext)]
    let tab: Tab?
    let foregroundColor: Color
    @State private var anchor = AnchorView()

    var body: some View {
        Menu {
            ForEach(items, id: \.record.id) { item in
                let action = item.context.action(for: tab.map { WebExtensionsManager.shared.adapter(for: $0) })
                Button {
                    WebExtensionsManager.shared.performAction(item.context, for: tab, anchor: anchor.view)
                } label: {
                    if let image = action?.icon(for: CGSize(width: 16, height: 16)) {
                        Label { Text(item.record.name) } icon: { Image(nsImage: image) }
                    } else {
                        Text(item.record.name)
                    }
                }
            }
            Divider()
            Button("Manage Extensions…") { BrowserWindows.showSettings(.extensions) }
        } label: {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(foregroundColor.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(AnchorReader(anchor: anchor, extensionID: nil))
        .help("Extensions")
    }
}

@available(macOS 15.4, *)
private struct ExtensionIcon: View {
    let action: WKWebExtension.Action?
    let foregroundColor: Color
    /// The website wants a decision: a dot, like Safari.
    var wantsAccess = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = action?.icon(for: CGSize(width: 16, height: 16)) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 13))
                    .foregroundColor(foregroundColor.opacity(0.7))
                    .frame(width: 16, height: 16)
            }
            if let badge = action?.badgeText, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 2)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 5, y: -4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if wantsAccess {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

/// Holds a button's view, for the popup to show under it.
@MainActor
private final class AnchorView {
    weak var view: NSView?
}

/// Reads the button's view; an extension's button is also kept for its
/// keyboard shortcuts (their popup shows under it).
@available(macOS 15.4, *)
private struct AnchorReader: NSViewRepresentable {
    let anchor: AnchorView
    let extensionID: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
        if let extensionID {
            WebExtensionsManager.shared.buttonAnchors.setObject(nsView, forKey: extensionID as NSString)
        }
    }
}
