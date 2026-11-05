import SwiftUI

struct FloatingURLBar: View {
    @EnvironmentObject private var sidebarManager: SidebarManager
    @Binding var showFloatingURLBar: Bool
    @Binding var isMouseOverURLBar: Bool

    private var triggerAreaPadding: CGFloat {
        showFloatingURLBar ? 50 : 16
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showFloatingURLBar {
                URLBar(
                    onSidebarToggle: { sidebarManager.toggleSidebar() }
                )
                .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separatorColor)),
                    alignment: .bottom
                )
                // Its address field is an AppKit view: a fade, not a move.
                .transition(.opacity)
                .zIndex(1)
            }

            VStack(alignment: .leading) {
                hoverStrip(width: .infinity)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: triggerAreaPadding)
        }
        .animation(.easeInOut(duration: 0.1), value: showFloatingURLBar)
    }

    private func hoverStrip(width: CGFloat) -> some View {
        Color.clear
            .overlay(
                GlobalMouseTrackingArea(
                    mouseEntered: Binding(
                        get: { showFloatingURLBar },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isMouseOverURLBar = newValue
                                showFloatingURLBar = newValue
                            }
                        }
                    ),
                    edge: .top,
                    padding: triggerAreaPadding,
                    slack: 8
                )
                .id(triggerAreaPadding)
            )
    }
}
