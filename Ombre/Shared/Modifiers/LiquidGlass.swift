import SwiftUI

/// Liquid Glass where Apple uses it (macOS 26), and before it the materials
/// Ombre already used. Nothing moves: the glass is never interactive.
extension View {
    /// A glass surface shaped like `shape` (macOS 26); before, `fallback`.
    /// `rim`: a light edge, brighter at the top left where the light comes
    /// from, for panels over a colored backdrop.
    @ViewBuilder
    func ombreGlass(
        in shape: some InsettableShape,
        rim: Bool = false,
        fallback: Material = .regularMaterial
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
                .overlay {
                    if rim {
                        shape.strokeBorder(Self.glassRim, lineWidth: 1).allowsHitTesting(false)
                    }
                }
        } else {
            background(fallback, in: shape)
        }
    }

    private static var glassRim: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.5), .white.opacity(0.12), .white.opacity(0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
