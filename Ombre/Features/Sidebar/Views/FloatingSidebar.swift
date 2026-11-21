import SwiftUI

struct FloatingSidebar: View {
    @Environment(\.theme) var theme
    @Environment(\.usesSidebarGlass) private var usesGlass

    let sidebarCornerRadius: CGFloat = {
        if #available(macOS 26, *) {
            return 13
        } else {
            return 5
        }
    }()

    var body: some View {
        let clipShape = ConditionallyConcentricRectangle(cornerRadius: sidebarCornerRadius)

        ZStack(alignment: .leading) {
            if usesGlass {
                glassSidebar
            } else {
                classicSidebar(clipShape: clipShape)
            }
        }
        .padding(6)
    }

    /// Glass over the page, faintly tinted with the space's color.
    @ViewBuilder
    private var glassSidebar: some View {
        if #available(macOS 26, *) {
            SidebarView()
                .clipShape(SidebarGlass.panelShape)
                .glassEffect(.regular.tint(theme.sidebarGlassTint), in: SidebarGlass.panelShape)
                .overlay {
                    SidebarGlass.panelShape
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }

    private func classicSidebar(clipShape: ConditionallyConcentricRectangle) -> some View {
        SidebarView()
            .background(theme.subtleWindowBackgroundColor)
            .background(BlurEffectView(material: .popover, blendingMode: .withinWindow))
            .clipShape(clipShape)
            .overlay(clipShape
                .stroke(theme.invertedSolidWindowBackgroundColor.opacity(0.3), lineWidth: 1)
            )
    }
}
