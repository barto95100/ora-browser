import AppKit
import SwiftUI

struct URLBarButton: View {
    let systemName: String
    let isEnabled: Bool
    let foregroundColor: Color
    let action: () -> Void
    /// What VoiceOver says; by default, named after the symbol.
    var label: String?
    @State private var isHovering = false

    private var cornerRadius: CGFloat {
        if #available(macOS 26, *) {
            return 10
        } else {
            return 10
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ?
                    (isHovering ? foregroundColor : foregroundColor.opacity(0.7)) :
                    foregroundColor.opacity(0.25)
                )
                .frame(width: 30, height: 30)
                .background(
                    ConditionallyConcentricRectangle(cornerRadius: cornerRadius)
                        .fill(isHovering && isEnabled ? foregroundColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .modifier(OptionalAccessibilityLabel(label: label ?? Self.label(for: systemName)))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

extension URLBarButton {
    /// The name of a toolbar button from its symbol, for VoiceOver.
    /// Nil for another symbol: SwiftUI names it.
    static func label(for systemName: String) -> String? {
        switch systemName {
        case "chevron.left": String(localized: "Back")
        case "chevron.right": String(localized: "Forward")
        case "arrow.clockwise": String(localized: "Reload")
        case "sidebar.left", "sidebar.right": String(localized: "Toggle Sidebar")
        case "square.and.arrow.up": String(localized: "Share")
        default: nil
        }
    }
}

private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}
