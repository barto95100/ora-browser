import SwiftUI

/// The pieces of the Liquid Glass sidebar (see `SidebarStyle`). Only the
/// panel is real glass; what is in it only looks like glass (`GlassPill`):
/// glass in glass is drawn over the text next to it.
enum SidebarGlass {
    static let panelRadius: CGFloat = 13

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
    }
}

extension View {
    /// The fixed sidebar: a glass panel over the space's background, with a
    /// gap around it like the page next to it.
    func sidebarGlassPanel() -> some View {
        modifier(SidebarGlassPanel())
    }

    /// A row's background: the glass pill when it is the active tab and the
    /// sidebar is glass, else `color`.
    func sidebarRowBackground(isActive: Bool, color: Color, cornerRadius: CGFloat) -> some View {
        modifier(SidebarRowBackground(isActive: isActive, color: color, cornerRadius: cornerRadius))
    }

    /// A field or bar on the glass panel (the address, the bottom buttons):
    /// faintly filled, with a light edge. `isHovering` fills it a little more.
    func sidebarGlassField(cornerRadius: CGFloat, isHovering: Bool = false) -> some View {
        modifier(SidebarGlassField(cornerRadius: cornerRadius, isHovering: isHovering))
    }
}

private struct SidebarGlassPanel: ViewModifier {
    @Environment(\.usesSidebarGlass) private var usesGlass

    func body(content: Content) -> some View {
        if usesGlass {
            content
                .clipShape(SidebarGlass.panelShape)
                .ombreGlass(in: SidebarGlass.panelShape, rim: true)
                .padding(6)
                .environment(\.isInSidebarGlassPanel, true)
        } else {
            content
        }
    }
}

private struct SidebarRowBackground: ViewModifier {
    let isActive: Bool
    let color: Color
    let cornerRadius: CGFloat
    @Environment(\.usesSidebarGlass) private var usesGlass
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            if usesGlass, isActive {
                let pill = theme.sidebarPill
                GlassPill(tint: Color(hex: pill.tintHex), fillOpacity: pill.opacity, shape: shape)
                    .shadow(color: .black.opacity(theme.sidebarPillNeedsShadow ? 0.12 : 0), radius: 1.5, y: 0.5)
            } else {
                shape.fill(color)
            }
        }
    }
}

private struct SidebarGlassField: ViewModifier {
    let cornerRadius: CGFloat
    let isHovering: Bool
    @Environment(\.usesSidebarGlass) private var usesGlass

    func body(content: Content) -> some View {
        if usesGlass {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(Color.primary.opacity(isHovering ? 0.09 : 0.05), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
