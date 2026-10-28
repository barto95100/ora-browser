import SwiftUI

/// "Private" in the address bar of private windows, like Safari, so they are
/// never mistaken for a regular window.
struct PrivateBrowsingBadge: View {
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Private")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(foregroundColor.opacity(0.14))
        )
        .fixedSize()
        .help("Private Browsing: history, cookies and site data of this window are not kept")
        .accessibilityLabel(Text("Private Browsing"))
    }
}
