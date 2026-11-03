import AppKit
import SwiftUI

struct NewContainerButton: View {
    @State private var isHovering = false

    @Environment(\.theme) private var theme
    @EnvironmentObject var dialogManager: DialogManager
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        Button(action: {
            dialogManager.show { id in
                SpaceEditorView(container: nil, dismiss: { dialogManager.dismiss(id: id) })
                    .environmentObject(tabManager)
                    .environmentObject(dialogManager)
            }
        }) {
            HStack {
                Image(systemName: "plus")
                    .frame(width: 12, height: 12)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
