import SwiftData
import SwiftUI

/// Creates or edits a space: name, icon (a symbol or an emoji), color and
/// theme.
/// Editing shows the changes right away; Cancel puts the space back as it was.
struct SpaceEditorView: View {
    /// The space edited, or nil to create one.
    let container: TabContainer?
    /// A new space becomes the window's one (the sidebar's "+"), or is only
    /// added (from the settings, which stay where they were).
    var switchesToNewSpace = true
    let dismiss: () -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var dialogManager: DialogManager

    @State private var look = SpaceLook(name: "")
    /// The space before editing, put back by Cancel.
    @State private var original: SpaceLook?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(container == nil ? "New Space" : "Edit Space")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.foreground)

            OmbreInput(
                text: $look.name,
                placeholder: String(localized: "Name (work, streaming, finance...)"),
                onSubmit: save
            )
            .focused($isNameFocused)

            SpaceLookFields(look: $look)

            HStack {
                if let container, tabManager.canDeleteSpace(container) {
                    Button("Delete…", action: confirmDelete)
                        .buttonStyle(.plain)
                        .foregroundColor(theme.destructive)
                }
                Spacer()
                OmbreButton(
                    label: String(localized: "Cancel"),
                    variant: .secondary,
                    keyboardShortcut: "esc",
                    action: cancel
                )
                OmbreButton(
                    label: String(localized: "OK"),
                    isDisabled: trimmedName.isEmpty,
                    keyboardShortcut: "return",
                    action: save
                )
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(theme.popoverBackground)
        .cornerRadius(14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear(perform: setUp)
        // Editing: the space shows its new look right away.
        .onChange(of: look) { old, new in
            // The name only changes with OK.
            if SpaceLook(old, name: "") != SpaceLook(new, name: "") { applyLive() }
        }
    }

    private var trimmedName: String {
        look.trimmedName
    }

    // MARK: - Actions

    private func setUp() {
        if let container {
            look = SpaceLook(of: container)
            original = look
        }
        isNameFocused = true
    }

    private func applyLive() {
        guard let container else { return }
        tabManager.updateSpace(container, look: SpaceLook(look, name: container.name))
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let saved = SpaceLook(look, name: trimmedName)
        if let container {
            tabManager.updateSpace(container, look: saved)
        } else {
            Self.createSpace(saved, in: tabManager, switchingToIt: switchesToNewSpace)
        }
        dismiss()
    }

    private func cancel() {
        if let container, let original {
            tabManager.updateSpace(container, look: original)
        }
        dismiss()
    }

    private func confirmDelete() {
        guard let container else { return }
        cancel()
        dialogManager.confirm(
            title: String(localized: "Delete \"\(container.name)\"?"),
            message: String(localized: "All tabs in this space will be permanently removed."),
            icon: .spaceCards,
            confirmLabel: String(localized: "Delete"),
            variant: .destructive
        ) {
            tabManager.deleteContainer(container)
        }
    }
}

extension TabManager {
    /// The last space cannot be deleted.
    func canDeleteSpace(_ container: TabContainer) -> Bool {
        let count = (try? modelContext.fetchCount(FetchDescriptor<TabContainer>())) ?? 0
        return count > 1
    }
}

@MainActor
extension SpaceEditorView {
    /// A new space, made the window's one or only added.
    @discardableResult
    static func createSpace(_ look: SpaceLook, in tabManager: TabManager, switchingToIt: Bool) -> TabContainer {
        if switchingToIt { return tabManager.createSpace(look: look) }
        let space = tabManager.addSpace(look: look)
        tabManager.modelContext.saveOrLog("add space")
        return space
    }

    /// The editor of a new space, over a browser window: from the sidebar's
    /// "+" and from Settings › Spaces (see `BrowserWindows.newSpace`).
    @discardableResult
    static func showNewSpace(
        dialogManager: DialogManager,
        tabManager: TabManager,
        switchesToNewSpace: Bool = true
    ) -> String {
        dialogManager.show { id in
            SpaceEditorView(
                container: nil,
                switchesToNewSpace: switchesToNewSpace,
                dismiss: { dialogManager.dismiss(id: id) }
            )
            .environmentObject(tabManager)
            .environmentObject(dialogManager)
        }
    }
}
