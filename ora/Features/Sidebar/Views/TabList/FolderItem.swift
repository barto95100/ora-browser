import SwiftUI

/// A folder of the pinned section, like Arc: a click opens or closes it right
/// away (no double click to wait for); Rename is in its context menu.
struct FolderItem: View {
    let folder: Folder
    let isDragging: Bool
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingFolderID == folder.id
    }

    var body: some View {
        HStack(spacing: 8) {
            // Like Arc: no arrow, the folder itself shows whether it is open.
            FolderGlyph(isOpen: folder.isOpened, color: theme.foreground)
                .frame(width: 16, height: 16)
            if isRenaming {
                TextField("Folder Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isNameFocused)
                    .onSubmit(endRenaming)
                    .onExitCommand { tabManager.renamingFolderID = nil }
                    .onAppear {
                        name = folder.name
                        DispatchQueue.main.async { isNameFocused = true }
                    }
                    .onChange(of: isNameFocused) { _, isFocused in
                        if !isFocused { endRenaming() }
                    }
            } else {
                Text(folder.name)
                    .font(.system(size: 13))
                    .foregroundColor(theme.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .opacity(isDragging ? 0.0 : 1.0)
        .background(backgroundColor, in: .rect(cornerRadius: 10))
        .overlay(
            isDragging ?
                ConditionallyConcentricRectangle(cornerRadius: 10)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                : nil
        )
        .contentShape(ConditionallyConcentricRectangle(cornerRadius: 10))
        .onTapGesture {
            guard !isRenaming else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                tabManager.toggleFolder(folder)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: startRenaming) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button {
                tabManager.createFolder(in: folder.container, parent: folder)
            } label: {
                Label("New Folder Inside", systemImage: "folder.badge.plus")
            }
            Button {
                tabManager.createFolder(in: folder.container, parent: folder.container.parent(of: folder))
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            moveMenu
            Divider()
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    tabManager.deleteFolder(folder)
                }
            } label: {
                Label("Delete Folder", systemImage: "folder.badge.minus")
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
    }

    /// Into another folder (not itself nor one of its own), or out of its folder.
    @ViewBuilder
    private var moveMenu: some View {
        let container = folder.container
        let targets = container.folders(acceptingFolder: folder)
            .filter { $0.id != folder.parentID }
            .sorted { container.path(of: $0) < container.path(of: $1) }
        if !targets.isEmpty {
            Menu("Move to Folder") {
                ForEach(targets) { target in
                    Button(container.path(of: target)) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            tabManager.moveFolder(folder, into: target)
                        }
                    }
                }
            }
        }
        if folder.parentID != nil {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    tabManager.moveFolder(folder, into: container.parent(of: folder).flatMap(container.parent(of:)))
                }
            } label: {
                Label("Move Out of Folder", systemImage: "arrow.up.left")
            }
        }
    }

    private var backgroundColor: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isHovering {
            return theme.activeTabBackground.opacity(colorScheme == .dark ? 0.3 : 0.1)
        }
        return .clear
    }

    private func startRenaming() {
        tabManager.renamingFolderID = folder.id
    }

    private func endRenaming() {
        guard isRenaming else { return }
        tabManager.renameFolder(folder, to: name)
        tabManager.renamingFolderID = nil
    }
}

/// Folder icon: closed, or open with its front flap tilted, like Arc's (SF
/// Symbols has no open folder).
struct FolderGlyph: View {
    let isOpen: Bool
    let color: Color

    var body: some View {
        if isOpen {
            ZStack {
                OpenFolderBack()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                OpenFolderFlap()
                    .fill(color.opacity(0.25))
                OpenFolderFlap()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
            .padding(.vertical, 2)
        } else {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
        }
    }
}

/// Back of an open folder, with its tab.
private struct OpenFolderBack: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + width * 0.04, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.04, y: rect.minY + height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.36, y: rect.minY + height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.46, y: rect.minY + height * 0.24))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.84, y: rect.minY + height * 0.24))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.84, y: rect.minY + height * 0.42))
        return path
    }
}

/// Front flap of an open folder, tilted forward.
private struct OpenFolderFlap: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + width * 0.2, y: rect.minY + height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.82, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.04, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
