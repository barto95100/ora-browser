import SwiftUI

/// Liquid Glass where Apple uses it (macOS 26), and before it the materials
/// Ombre already used. Nothing moves: glass only reacts to the pointer on
/// controls that ask for it.
extension View {
    /// A glass surface shaped like `shape` (macOS 26); before, `fallback`.
    @ViewBuilder
    func ombreGlass(
        in shape: some Shape,
        tint: Color? = nil,
        isInteractive: Bool = false,
        fallback: Material = .regularMaterial
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// Glass buttons (macOS 26); before, bordered ones. `prominent`: the
    /// main action of its place, filled with the tint.
    @ViewBuilder
    func ombreButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Glass surfaces drawn together (macOS 26), so that close ones blend like
/// Apple's; before, its content as it is.
struct OmbreGlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
