import SwiftUI

/// The pieces of the Liquid Glass sidebar (see `GlassEffects`). Only the
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
    @Environment(\.usesGlassEffects) private var usesGlass

    func body(content: Content) -> some View {
        if usesGlass {
            content
                .clipShape(SidebarGlass.panelShape)
                .sidebarGlassSurface()
                .padding(6)
                .environment(\.isInSidebarGlassPanel, true)
        } else {
            content
        }
    }
}

extension View {
    /// The glass of a sidebar panel, more marked than the settings': a
    /// reflection along its top, a bright edge, and a soft shadow around it.
    /// `tint`: the floating sidebar's, over the page.
    func sidebarGlassSurface(tint: Color? = nil) -> some View {
        modifier(SidebarGlassSurface(tint: tint))
    }
}

private struct SidebarGlassSurface: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = SidebarGlass.panelShape
        if #available(macOS 26, *) {
            content
                // Over the glass, under the tabs.
                .background(alignment: .top) {
                    GlassRim.reflection
                        .frame(height: GlassRim.reflectionHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay {
                    shape.strokeBorder(GlassRim.strong, lineWidth: 1).allowsHitTesting(false)
                }
                .background { SidebarPanelShadow(shape: shape) }
        } else {
            content
        }
    }
}

/// A soft shadow around the panel, kept out of it: the glass shows what is
/// behind it, and a shadow inside would darken it.
private struct SidebarPanelShadow: View {
    let shape: RoundedRectangle

    var body: some View {
        shape
            .fill(Color.black.opacity(0.25))
            // Within the panel's 6 pt margin, mostly.
            .blur(radius: 5)
            .offset(y: 2)
            .mask {
                Rectangle()
                    .padding(-30)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

private struct SidebarRowBackground: ViewModifier {
    let isActive: Bool
    let color: Color
    let cornerRadius: CGFloat
    @Environment(\.usesGlassEffects) private var usesGlass
    @Environment(\.theme) private var theme
    @Environment(\.usesTranslucentWindow) private var isTranslucent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            if usesGlass, isActive {
                let pill = theme.sidebarPill(translucent: isTranslucent)
                GlassPill(
                    tint: Color(hex: pill.tintHex),
                    fillOpacity: pill.opacity,
                    highlightOpacity: SidebarGlassPalette.pillHighlight,
                    rimOpacity: 0.65,
                    shape: shape
                )
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
    @Environment(\.usesGlassEffects) private var usesGlass

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
