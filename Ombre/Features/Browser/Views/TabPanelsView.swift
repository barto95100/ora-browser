import AppKit
import SwiftUI

/// The pages a window shows: the active tab, or both sides of its split (like
/// Arc) with a divider to drag. Each page keeps its place while a split is
/// made or undone, so it is never moved to another view (it would show blank).
/// In a split, the focused side (the active tab) is outlined and a click in
/// the other side focuses it.
struct TabPanelsView: View {
    /// The active tab, or a split's left and right tabs.
    let tabs: [Tab]
    let focusedTabID: UUID
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    /// Width share shown while the divider is dragged, saved when it is released.
    @State private var dragFraction: Double?
    @State private var dragStartFraction: Double?
    @State private var hoveredPanelID: UUID?
    @State private var mouseDown = MouseDownMonitor()

    private static let gap: CGFloat = 8

    private var isSplit: Bool {
        tabs.count == 2
    }

    private var leftFraction: Double {
        TabSplits.clampedFraction(dragFraction ?? tabs.first?.splitFraction ?? 0.5)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - (isSplit ? Self.gap : 0), 1)
            let leftWidth = availableWidth * CGFloat(leftFraction)
            HStack(spacing: isSplit ? Self.gap : 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    panel(tab)
                        .frame(width: isSplit && index == 0 ? leftWidth : nil)
                }
            }
            .overlay(alignment: .leading) {
                if isSplit {
                    divider(availableWidth: availableWidth)
                        // Padding, not an offset: the handle must really be
                        // there, not only drawn there.
                        .padding(.leading, leftWidth)
                }
            }
        }
        .onAppear {
            mouseDown.start { focusClickedPanel(for: $0) }
        }
        .onDisappear {
            mouseDown.stop()
        }
    }

    private func panel(_ tab: Tab) -> some View {
        let cornerRadius: CGFloat = isSplit ? 8 : 0
        return TabPageContent(tab: tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Filled while a page catches up with a new width (divider dragged).
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSplit && tab.id == focusedTabID ? theme.foreground.opacity(0.3) : .clear,
                        lineWidth: 2
                    )
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) {
                if isSplit, hoveredPanelID == tab.id {
                    Button {
                        tabManager.closeTab(tab: tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.foreground)
                            .frame(width: 22, height: 22)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hoveredPanelID)
            .onHover { hovering in
                if hovering {
                    hoveredPanelID = tab.id
                } else if hoveredPanelID == tab.id {
                    hoveredPanelID = nil
                }
            }
            .onAppear {
                guard isSplit else { return }
                tabManager.loadIfNeeded(tab)
                tab.recoverFromCrashIfNeeded()
            }
    }

    /// The space between the two sides: shows the resize pointer and is dragged.
    private func divider(availableWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: Self.gap)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                // Global: the handle moves with the drag.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { resize(by: $0.translation.width, availableWidth: availableWidth) }
                    .onEnded { _ in endResize() }
            )
    }

    private func resize(by translation: CGFloat, availableWidth: CGFloat) {
        guard isSplit, let left = tabs.first else { return }
        let start = dragStartFraction ?? left.splitFraction
        dragStartFraction = start
        dragFraction = TabSplits.clampedFraction(start + Double(translation / availableWidth))
    }

    private func endResize() {
        if isSplit, let left = tabs.first, let dragFraction {
            left.splitFraction = dragFraction
            tabManager.saveSplitLayout()
        }
        dragFraction = nil
        dragStartFraction = nil
    }

    /// A click in the side of a split that is not focused focuses it (Peek,
    /// shown over both sides, takes its own clicks).
    private func focusClickedPanel(for event: NSEvent) {
        // Tracing an area for a note: the click is for the capture.
        guard tabManager.peek == nil, appState.areaCapture == nil, let active = tabManager.activeTab else { return }
        for tab in tabManager.shownTabs(around: active) where tab.id != active.id {
            guard let webView = tab.browserPage?.webView,
                  let window = webView.window,
                  window === event.window
            else { continue }
            let point = webView.convert(event.locationInWindow, from: nil)
            if webView.bounds.contains(point) {
                tabManager.activateTab(tab)
                return
            }
        }
    }
}
