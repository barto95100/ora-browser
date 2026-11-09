import SwiftUI

/// What VoiceOver says of the sidebar's rows, and what it can do with them
/// (INT-11): tabs and folders were only tappable, unnamed images and text.
enum TabAccessibility {
    static func label(title: String, url: URL) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (url.host ?? url.absoluteString) : title
    }

    static func value(isLoaded: Bool, isPlayingMedia: Bool) -> String {
        // Shown: the selected trait says it.
        var parts: [String] = []
        if !isLoaded { parts.append(String(localized: "Not loaded")) }
        if isPlayingMedia { parts.append(String(localized: "Playing audio")) }
        return parts.joined(separator: ", ")
    }
}

extension View {
    /// A tab's row: one element, a button that shows the tab, with its
    /// other actions named (close, pin…).
    func tabAccessibility(
        tab: Tab,
        isSelected: Bool,
        activate: @escaping () -> Void,
        actions: [(name: String, action: () -> Void)]
    ) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(TabAccessibility.label(title: tab.title, url: tab.url))
            .accessibilityValue(TabAccessibility.value(
                isLoaded: tab.isWebViewReady,
                isPlayingMedia: tab.isPlayingMedia
            ))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default) { activate() }
            .modifier(NamedAccessibilityActions(actions: actions))
    }
}

private struct NamedAccessibilityActions: ViewModifier {
    let actions: [(name: String, action: () -> Void)]

    func body(content: Content) -> some View {
        actions.reduce(AnyView(content)) { view, item in
            AnyView(view.accessibilityAction(named: Text(item.name), item.action))
        }
    }
}
