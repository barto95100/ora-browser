import SwiftUI

/// What shows under the glass sidebar, until one is chosen (the Debug menu
/// switches live): the desktop through the window, or the space's color as
/// before. Only with Glass Effects on.
enum SidebarBackground: String, CaseIterable, Identifiable {
    case translucentWindow
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
        case .spaceColor: String(localized: "Space Color")
        }
    }

    static var debugMenuTitle: String {
        String(localized: "Sidebar Background")
    }
}

extension EnvironmentValues {
    /// The desktop shows through the window under the glass sidebar.
    @Entry var usesTranslucentWindow = false
}

extension View {
    /// Sets `usesTranslucentWindow`: glass on, and the translucent window
    /// chosen. Inside `glassEffectsEnvironment()`.
    func translucentWindowEnvironment() -> some View {
        modifier(TranslucentWindowEnvironment())
    }
}

private struct TranslucentWindowEnvironment: ViewModifier {
    @Environment(\.usesGlassEffects) private var usesGlass
    @AppStorage(SidebarBackground.defaultsKey) private var background = SidebarBackground.defaultValue

    func body(content: Content) -> some View {
        content.environment(\.usesTranslucentWindow, usesGlass && isTranslucentChosen)
    }

    /// Only Ombre Dev compares (the Debug menu): Release keeps the space's
    /// color until one is chosen.
    private var isTranslucentChosen: Bool {
        #if DEBUG
            background == .translucentWindow
        #else
            false
        #endif
    }
}

/// The window's background, under the sidebar and around the page: the
/// space's color as a gradient (as before), or, translucent, the desktop
/// with a scrim and the space's color over it (`SidebarGlassPalette`).
struct SpaceWindowBackground: View {
    let theme: Theme
    let key: String
    @Environment(\.usesTranslucentWindow) private var isTranslucent

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
            base.opacity(SidebarGlassPalette.translucentScrim(isDark: isDark))
            if theme.spaceTheme == nil, let tint = theme.spaceColor?.color {
                tint.opacity(SidebarGlassPalette.translucentSpaceTint)
            }
        }
    }
}
