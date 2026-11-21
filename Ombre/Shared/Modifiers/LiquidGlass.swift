import SwiftUI

/// Liquid Glass where Apple uses it (macOS 26, while `usesGlassEffects`),
/// and otherwise the materials Ombre already used. Nothing moves: the glass
/// is never interactive.
extension View {
    /// A glass surface shaped like `shape`; without glass, `fallback`.
    /// `rim`: a light edge, brighter at the top left where the light comes
    /// from, for panels over a colored backdrop.
    func ombreGlass(
        in shape: some InsettableShape,
        rim: Bool = false,
        fallback: Material = .regularMaterial
    ) -> some View {
        modifier(OmbreGlass(shape: shape, rim: rim, fallback: fallback))
    }

    /// Glass buttons; without glass, bordered ones. `prominent`: the main
    /// action of its place, filled with the tint.
    func ombreButtonStyle(prominent: Bool = false) -> some View {
        modifier(OmbreButtonStyle(prominent: prominent))
    }
}

/// The light edge of glass panels, brighter at the top left.
enum GlassRim {
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.5), .white.opacity(0.12), .white.opacity(0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Brighter, for the sidebar: it shows even on a light space.
    static var strong: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.85), .white.opacity(0.25), .white.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A reflection along the top of a panel, over its first
    /// `reflectionHeight` points only (the header, the top of the list).
    static var reflection: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.14), .white.opacity(0.03), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let reflectionHeight: CGFloat = 56
}

private struct OmbreGlass<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape
    let rim: Bool
    let fallback: Material
    @Environment(\.usesGlassEffects) private var usesGlass

    func body(content: Content) -> some View {
        if #available(macOS 26, *), usesGlass {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    if rim {
                        shape.strokeBorder(GlassRim.gradient, lineWidth: 1).allowsHitTesting(false)
                    }
                }
        } else {
            content.background(fallback, in: shape)
        }
    }
}

private struct OmbreButtonStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.usesGlassEffects) private var usesGlass

    func body(content: Content) -> some View {
        if #available(macOS 26, *), usesGlass {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
