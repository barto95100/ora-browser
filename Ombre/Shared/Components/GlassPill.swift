import SwiftUI

/// A selection pill that looks like glass: tinted, lighter at the top, with
/// a light edge. Not real glass: real glass in a glass panel is drawn over
/// its row's text, and this one also draws offscreen (tests) and on macOS 15.
/// Always in a `.background`, behind the row it marks.
struct GlassPill<PillShape: InsettableShape>: View {
    let tint: Color
    var fillOpacity = 0.32
    /// Its list has the arrow keys: the edge is the tint itself.
    var hasKeys = false
    /// The reflection at its top, and its light edge.
    var highlightOpacity = 0.16
    var rimOpacity = 0.4
    let shape: PillShape

    var body: some View {
        shape
            .fill(tint.opacity(fillOpacity))
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(highlightOpacity), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))
            }
            .overlay {
                if hasKeys {
                    shape.strokeBorder(tint, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(rimOpacity), tint.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                }
            }
            .allowsHitTesting(false)
    }
}
