import AppKit
import SwiftUI

/// Which pages the pager draws: the selected one, and the one it leaves while
/// the move to it runs. The others are empty frames: a space not shown costs
/// nothing.
struct SpacePagerLayout: Equatable {
    let count: Int
    let index: Int
    let leaving: Int?

    init(count: Int, selection: Int, leaving: Int?) {
        self.count = count
        let index = count == 0 ? 0 : min(max(selection, 0), count - 1)
        self.index = index
        self.leaving = leaving.flatMap { (0 ..< count).contains($0) && $0 != index ? $0 : nil }
    }

    func draws(_ page: Int) -> Bool {
        page == index || page == leaving
    }

    /// Pages are side by side; the row moves to show the selected one.
    func offset(width: CGFloat) -> CGFloat {
        -CGFloat(index) * width
    }
}

/// The spaces' pages in the sidebar, side by side, moved to the selected
/// one: animated when the selection changes inside an animation (a swipe, a
/// click on a space), at once otherwise. Plain SwiftUI: AppKit's page
/// controller crashed when the sidebar changed during its own swipe tracking
/// or its bounce. Swipes are read by the sidebar (`HorizontalSwipeMonitor`).
struct SpacePager<Page, Content: View>: View {
    let pages: [Page]
    let selection: Int
    let id: KeyPath<Page, String>
    @ViewBuilder let content: (Page) -> Content

    /// The page left by the last move (its identifier), drawn until the move
    /// has surely ended.
    @State private var leaving: String?
    @State private var leavingEnd: Task<Void, Never>?

    /// Longer than the sidebar's animations of a change of space (0.3 s).
    static var leavingDuration: Duration {
        .milliseconds(600)
    }

    private struct Entry: Identifiable {
        let id: String
        let position: Int
    }

    private var entries: [Entry] {
        pages.indices.map { Entry(id: pages[$0][keyPath: id], position: $0) }
    }

    var body: some View {
        let leavingIndex = leaving.flatMap { leaving in pages.firstIndex { $0[keyPath: id] == leaving } }
        let layout = SpacePagerLayout(count: pages.count, selection: selection, leaving: leavingIndex)
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                // By the page's identifier: a space deleted or moved keeps
                // each page's state with its own space.
                ForEach(entries) { entry in
                    let position = entry.position
                    let page = pages[position]
                    Group {
                        if layout.draws(position) {
                            content(page)
                        } else {
                            Color.clear
                        }
                    }
                    // Slides in and out with the row, without fading.
                    .transition(.identity)
                    .frame(width: width, height: geometry.size.height)
                    // Only the page shown takes clicks and drops: the page
                    // left is drawn beside the sidebar for a moment.
                    .allowsHitTesting(position == layout.index)
                }
            }
            .frame(width: width, alignment: .leading)
            .offset(x: layout.offset(width: width))
        }
        .clipped()
        .contentShape(Rectangle())
        .background(SpacePagerFrame())
        .onChange(of: selection) { previous, _ in
            leaving = pages.indices.contains(previous) ? pages[previous][keyPath: id] : nil
            leavingEnd?.cancel()
            leavingEnd = Task { @MainActor in
                try? await Task.sleep(for: Self.leavingDuration)
                guard !Task.isCancelled else { return }
                leaving = nil
            }
        }
        .onDisappear {
            leavingEnd?.cancel()
            leaving = nil
        }
    }
}

/// Marks where the pager is in its window (tests drop files on the sidebar).
private struct SpacePagerFrame: NSViewRepresentable {
    func makeNSView(context: Context) -> SpacePagerFrameView {
        SpacePagerFrameView()
    }

    func updateNSView(_ nsView: SpacePagerFrameView, context: Context) {}
}

final class SpacePagerFrameView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
