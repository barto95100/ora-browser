import SwiftData
import SwiftUI

/// What cannot be undone for a space, last on its page: clearing its data,
/// deleting it. Each with what it does, and a confirmation.
struct SpaceDangerZoneCard: View {
    let container: TabContainer
    /// False for the last space: it cannot be deleted.
    let canDelete: Bool
    /// Asks the page to confirm the deletion (see `SpacesSettingsView`).
    let onDelete: () -> Void

    @EnvironmentObject private var toastManager: ToastManager
    @Environment(\.modelContext) private var modelContext
    @State private var isChoosingDataToClear = false

    var body: some View {
        SettingsCard(header: String(localized: "Danger Zone")) {
            row(
                title: String(localized: "Clear Data"),
                detail: String(
                    localized: "This space’s cache, cookies or history. Its tabs stay; sites may sign you out."
                )
            ) {
                Button("Clear Data…") { isChoosingDataToClear = true }
                    .ombreButtonStyle()
                    .confirmationDialog(
                        "Clear data of “\(container.name)”?",
                        isPresented: $isChoosingDataToClear
                    ) {
                        Button("Clear Cache", role: .destructive) { clearCache() }
                        Button("Clear Cookies", role: .destructive) { clearCookies() }
                        Button("Clear History", role: .destructive) { clearHistory() }
                        Button("Clear All", role: .destructive) {
                            clearCache()
                            clearCookies()
                            clearHistory()
                        }
                    } message: {
                        Text("This can’t be undone.")
                    }
            }
            Divider()
            row(
                title: String(localized: "Delete Space"),
                detail: canDelete
                    ? String(localized: "Removes the space with its tabs, folders and website data.")
                    : String(localized: "The last space can't be deleted.")
            ) {
                Button("Delete Space…", role: .destructive, action: onDelete)
                    .ombreButtonStyle(prominent: true)
                    .tint(.red)
                    .disabled(!canDelete)
            }
        }
        .overlay {
            // Red-edged: what is here cannot be undone.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                .padding(.top, Self.headerHeight)
                .allowsHitTesting(false)
        }
    }

    /// The card's title above it, outside the red edge.
    private static let headerHeight: CGFloat = 24

    private func row(title: String, detail: String, @ViewBuilder button: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            button()
        }
    }

    private func clearCache() {
        PrivacyService.clearCache(container) {
            toastManager.show(String(localized: "Cache cleared"), icon: .system("trash"))
        }
    }

    private func clearCookies() {
        PrivacyService.clearCookies(container) {
            toastManager.show(String(localized: "Cookies cleared"), icon: .system("trash"))
        }
    }

    private func clearHistory() {
        let history = HistoryManager(modelContainer: modelContext.container, modelContext: modelContext)
        if history.clearContainerHistory(container) {
            toastManager.show(String(localized: "History cleared"), icon: .system("trash"))
        }
    }
}
