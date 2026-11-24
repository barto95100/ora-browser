import SwiftUI

/// A tab's name in the sidebar (see `TabName`), editable in place after
/// Rename… in its context menu, like Arc: Return keeps the name, Escape
/// leaves it as it was. No double click to rename: every single click would
/// wait for a possible second one.
struct TabNameText: View {
    let tab: Tab
    let font: Font
    let style: AnyShapeStyle
    @EnvironmentObject var tabManager: TabManager
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingTabID == tab.id
    }

    var body: some View {
        if isRenaming {
            // The page's title as placeholder: what an empty name goes back to.
            TextField(tab.title, text: $name)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isNameFocused)
                .onSubmit(endRenaming)
                .onExitCommand { tabManager.renamingTabID = nil }
                .onAppear {
                    name = tab.displayName
                    DispatchQueue.main.async { isNameFocused = true }
                }
                .onChange(of: isNameFocused) { _, isFocused in
                    if !isFocused { endRenaming() }
                }
        } else {
            Text(tab.displayName)
                .font(font)
                .foregroundStyle(style)
                .lineLimit(1)
        }
    }

    private func endRenaming() {
        guard isRenaming else { return }
        tabManager.renameTab(tab, to: name)
        tabManager.renamingTabID = nil
    }
}

/// Rename… and Restore Page Name, in a tab's context menu.
struct TabRenameMenuItems: View {
    let tab: Tab
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        Button {
            tabManager.renamingTabID = tab.id
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        if tab.customName != nil {
            Button {
                tabManager.renameTab(tab, to: "")
            } label: {
                Label("Restore Page Name", systemImage: "arrow.uturn.backward")
            }
        }
    }
}
