import AppKit
import SwiftUI
@preconcurrency import WebKit

/// The enabled extensions' buttons, right of the sidebar button (top of the
/// sidebar, or the address bar while the sidebar is hidden). As many as fit;
/// the others are in a menu. A click shows the extension's popup under it.
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
        // Redrawn when an extension changes its icon, badge or state.
        let revision = manager.actionsRevision
        let items = manager.loadedContexts
        let shown = ExtensionStripLayout.visibleCount(
            items: items.count,
            capacity: maxVisible ?? Int(width / Self.slot)
        )
        HStack(spacing: 0) {
            ForEach(items.prefix(shown), id: \.record.id) { item in
                ExtensionActionButton(
                    name: item.record.name,
                    context: item.context,
                    tab: tabManager.activeTab,
                    foregroundColor: foregroundColor
                )
                .id("\(item.record.id)-\(revision)")
            }
            if shown < items.count {
                ExtensionOverflowMenu(
                    items: Array(items.dropFirst(shown)),
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
/// leave room for the menu of the others.
enum ExtensionStripLayout {
    static func visibleCount(items: Int, capacity: Int) -> Int {
        let capacity = max(capacity, 0)
        return items <= capacity ? items : max(capacity - 1, 0)
    }
}

@available(macOS 15.4, *)
private struct ExtensionActionButton: View {
    let name: String
    let context: WKWebExtensionContext
    let tab: Tab?
    let foregroundColor: Color
    @State private var anchor = AnchorView()
    @State private var isHovering = false

    var body: some View {
        let action = context.action(for: tab.map { WebExtensionsManager.shared.adapter(for: $0) })
        Button {
            WebExtensionsManager.shared.performAction(context, for: tab, anchor: anchor.view)
        } label: {
            ExtensionIcon(action: action, foregroundColor: foregroundColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovering ? foregroundColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .background(AnchorReader(anchor: anchor))
        .opacity(action?.isEnabled == false ? 0.4 : 1)
        .help(action?.label ?? name)
        .accessibilityLabel(Text(action?.label ?? name))
    }
}

/// The extensions that don't fit; the chosen one's popup shows under it.
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
        .background(AnchorReader(anchor: anchor))
        .help("More Extensions")
    }
}

@available(macOS 15.4, *)
private struct ExtensionIcon: View {
    let action: WKWebExtension.Action?
    let foregroundColor: Color

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
    }
}

/// Holds a button's view, for the popup to show under it.
@MainActor
private final class AnchorView {
    weak var view: NSView?
}

private struct AnchorReader: NSViewRepresentable {
    let anchor: AnchorView

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
