import SwiftUI

extension EnvironmentValues {
    /// The desktop shows through the window under the glass sidebar (Glass
    /// Effects on). Off over the page (the floating sidebar).
    @Entry var usesTranslucentWindow = false
}

extension View {
    /// Sets `usesTranslucentWindow` from `usesGlassEffects`: inside
    /// `glassEffectsEnvironment()`.
    func translucentWindowEnvironment() -> some View {
        modifier(TranslucentWindowEnvironment())
    }
}

private struct TranslucentWindowEnvironment: ViewModifier {
    @Environment(\.usesGlassEffects) private var usesGlass

    func body(content: Content) -> some View {
        content.environment(\.usesTranslucentWindow, usesGlass)
    }
}

/// The window's background, under the sidebar and around the page: the
/// space's color as a gradient (without glass, as before), or, with glass,
/// the desktop through the window with a light scrim (Settings ›
/// Transparency) and the space's color over it (`SidebarGlassPalette`).
struct SpaceWindowBackground: View {
    let theme: Theme
    let key: String
    @Environment(\.usesTranslucentWindow) private var isTranslucent
    @Environment(\.glassTransparency) private var transparency

    private var isDark: Bool {
        theme.colorScheme == .dark || theme.spaceTheme != nil
    }

    var body: some View {
        ZStack {
            if isTranslucent {
                translucent
                    .id(key)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(theme.windowBackground)
                    .id(key)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: key)
        .background {
            // The desktop, blurred by macOS (behind the window).
            BlurEffectView(
                material: isTranslucent ? .sidebar : .underWindowBackground,
                blendingMode: .behindWindow
            )
        }
        .ignoresSafeArea(.all)
    }

    private var translucent: some View {
        let base: Color = theme.spaceTheme?.background ?? (isDark ? .black : .white)
        return ZStack {
            base.opacity(transparency.scrim(isDark: isDark))
            if theme.spaceTheme == nil, let tint = theme.spaceColor?.color {
                tint.opacity(SidebarGlassPalette.translucentSpaceTint)
            }
        }
    }
}
