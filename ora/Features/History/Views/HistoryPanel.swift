import AppKit
import SwiftUI

/// The space's history (⌘Y), over the page like the launcher (upstream
/// issue 185): search, pages grouped by day, open, delete, clear.
struct HistoryPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode
    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var entries: [History] = []
    @State private var selection: UUID?
    @State private var rangeToClear: HistoryClearRange?
    @FocusState private var isSearchFocused: Bool

    /// Enough to scroll back weeks without loading a whole history at once.
    private static let maxEntries = 500

    private var sections: [HistorySections.Section<History>] {
        HistorySections.byDay(entries, date: \.lastAccessedAt)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            panel
                .padding(.top, 80)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: close)
        .onAppear {
            isSearchFocused = true
            reload()
        }
        .onChange(of: query) { reload() }
        .confirmationDialog(
            "Clear \(rangeToClear?.title ?? "")?",
            isPresented: Binding(get: { rangeToClear != nil }, set: { if !$0 { rangeToClear = nil } }),
            presenting: rangeToClear
        ) { range in
            Button("Clear History", role: .destructive) { clear(range) }
        } message: { _ in
            Text("Pages visited in this space are removed from its history.")
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            if entries.isEmpty {
                Text(query.isEmpty ? "No history yet" : "No results")
                    .foregroundStyle(theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                list
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(maxWidth: 640, maxHeight: 560)
        .fixedSize(horizontal: false, vertical: entries.isEmpty)
        .background(theme.launcherMainBackground)
        .background(BlurEffectView(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.foreground.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 40, x: 0, y: 24)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.mutedForeground)
            TextField("Search History", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit { open(selectedEntry, inBackground: false) }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
        }
        .padding(14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.items) { entry in
                                row(entry).id(entry.id)
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(theme.launcherMainBackground)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ entry: History) -> some View {
        HStack(spacing: 10) {
            FavIcon(
                isWebViewReady: true,
                favicon: entry.faviconURL,
                faviconLocalFile: entry.faviconLocalFile,
                textColor: theme.foreground
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? entry.urlString : entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                Text(entry.url.host ?? entry.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.lastAccessedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedForeground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == entry.id ? theme.foreground.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { selection = entry.id } }
        .onTapGesture {
            open(entry, inBackground: NSEvent.modifierFlags.contains(.command))
        }
        .contextMenu {
            Button("Open in New Tab") { open(entry, inBackground: false) }
            Button("Open in Background") { open(entry, inBackground: true) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.urlString, forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) {
                historyManager.delete(entry)
                reload()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("⌘-click opens in the background")
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedForeground)
            Spacer()
            Menu("Clear History…") {
                ForEach(HistoryClearRange.allCases) { range in
                    Button("Clear \(range.title)…") { rangeToClear = range }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var selectedEntry: History? {
        entries.first { $0.id == selection } ?? entries.first
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !entries.isEmpty else { return .handled }
        let current = entries.firstIndex { $0.id == selection } ?? -offset
        let next = min(max(current + offset, 0), entries.count - 1)
        selection = entries[next].id
        return .handled
    }

    private func reload() {
        guard let containerId = tabManager.activeContainer?.id else {
            entries = []
            return
        }
        entries = Array(historyManager.search(query, activeContainerId: containerId).prefix(Self.maxEntries))
        selection = entries.first?.id
    }

    private func open(_ entry: History?, inBackground: Bool) {
        guard let entry else { return }
        tabManager.openTab(
            url: entry.url,
            historyManager: historyManager,
            downloadManager: downloadManager,
            focusAfterOpening: !inBackground,
            isPrivate: privacyMode.isPrivate,
            loadSilently: inBackground
        )
        if !inBackground { close() }
    }

    private func clear(_ range: HistoryClearRange) {
        guard let container = tabManager.activeContainer else { return }
        historyManager.clear(range, in: container)
        rangeToClear = nil
        reload()
    }

    private func close() {
        appState.showHistory = false
    }
}
