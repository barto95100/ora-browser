import SwiftUI

/// The addresses of tabs, as copied from the sidebar: one per line, in the
/// order given (the sidebar's).
enum TabAddresses {
    static func text(for tabs: [Tab]) -> String {
        tabs.map(\.url.absoluteString).joined(separator: "\n")
    }

    /// Copies them, with the usual confirmation.
    @MainActor
    static func copy(_ tabs: [Tab], toastManager: ToastManager = .shared) {
        guard !tabs.isEmpty else { return }
        ClipboardUtils.copyWithToast(
            text(for: tabs),
            message: tabs.count == 1 ? String(localized: "Link copied") : String(localized: "Links copied"),
            toastManager: toastManager
        )
    }
}

/// "Copy Address" in a tab's context menu, like Arc.
struct CopyTabAddressButton: View {
    let tab: Tab

    var body: some View {
        Button {
            TabAddresses.copy([tab])
        } label: {
            Label("Copy Address", systemImage: "link")
        }
    }
}
