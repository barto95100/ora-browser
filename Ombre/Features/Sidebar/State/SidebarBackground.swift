import SwiftUI

/// What shows under the glass sidebar, until one is chosen (the Debug menu
/// switches live): the desktop through the window, the same with a tint of
/// the active site's color, or the space's color as before. Only with Glass
/// Effects on.
enum SidebarBackground: String, CaseIterable, Identifiable {
    case translucentWindow
    case siteTint
    case spaceColor

    static let defaultsKey = "debug.sidebarBackground"
    static let defaultValue = SidebarBackground.translucentWindow

    var id: String {
        rawValue
    }

    /// Its name in the Debug menu (outside `#if DEBUG`, so that the
    /// localization check, which reads the Release build, sees it).
    var title: String {
        switch self {
        case .translucentWindow: String(localized: "Translucent Window")
        case .siteTint: String(localized: "Site Tint")
        case .spaceColor: String(localized: "Space Color")
        }
    }

    static var debugMenuTitle: String {
        String(localized: "Sidebar Background")
    }

    var isTranslucent: Bool {
        self != .spaceColor
    }
}

extension EnvironmentValues {
    /// The desktop shows through the window under the glass sidebar.
    @Entry var usesTranslucentWindow = false
    /// And the active site's color tints it.
    @Entry var usesSiteTint = false
}

extension View {
    /// Sets `usesTranslucentWindow` and `usesSiteTint`: glass on, and that
    /// background chosen. Inside `glassEffectsEnvironment()`.
    func translucentWindowEnvironment() -> some View {
        modifier(TranslucentWindowEnvironment())
    }
}

private struct TranslucentWindowEnvironment: ViewModifier {
    @Environment(\.usesGlassEffects) private var usesGlass
    @AppStorage(SidebarBackground.defaultsKey) private var background = SidebarBackground.defaultValue

    func body(content: Content) -> some View {
        content
            .environment(\.usesTranslucentWindow, usesGlass && chosen.isTranslucent)
            .environment(\.usesSiteTint, usesGlass && chosen == .siteTint)
    }

    /// Only Ombre Dev compares (the Debug menu): Release keeps the space's
    /// color until one is chosen.
    private var chosen: SidebarBackground {
        #if DEBUG
            background
        #else
            .spaceColor
        #endif
    }
}

/// The window's background, under the sidebar and around the page: the
/// space's color as a gradient (as before), or, translucent, the desktop
/// with a scrim, the space's color and maybe the site's over it
/// (`SidebarGlassPalette`).
struct SpaceWindowBackground: View {
    let theme: Theme
    let key: String
    /// The active tab, for its site's color (`Tab.backgroundColorHex`).
    let siteTab: Tab?
    @Environment(\.usesTranslucentWindow) private var isTranslucent
    @Environment(\.usesSiteTint) private var usesSiteTint
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
            if usesSiteTint, let siteHex = Self.siteHex(of: siteTab) {
                // Faded from one tab's color to the next.
                SidebarGlassPalette.siteTintColor(siteHex, isDark: isDark).color
                    .opacity(SidebarGlassPalette.siteTint)
                    .animation(.easeOut(duration: 0.35), value: siteHex)
            }
        }
    }

    /// Read only for the site tint, so that nothing else redraws when a
    /// page's color is found. Black is also what an unknown color is saved
    /// as: no tint then.
    static func siteHex(of tab: Tab?) -> String? {
        guard let hex = tab?.backgroundColorHex, !hex.uppercased().hasPrefix("#000000") else { return nil }
        return hex
    }
}
