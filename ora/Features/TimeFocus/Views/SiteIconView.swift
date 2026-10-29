import SwiftUI

/// A site's icon, from the history; its initial when it has none.
struct SiteIconView: View {
    let domain: String
    var size: CGFloat = 18
    @EnvironmentObject var historyManager: HistoryManager
    @Environment(\.theme) private var theme
    @State private var icon: SiteIcon?

    var body: some View {
        Group {
            if let icon {
                FavIcon(
                    isWebViewReady: true,
                    favicon: icon.url,
                    faviconLocalFile: icon.localFile,
                    textColor: theme.foreground
                )
            } else {
                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(theme.accent.opacity(0.8), in: RoundedRectangle(cornerRadius: size * 0.28))
            }
        }
        .frame(width: size, height: size)
        .task(id: domain) { icon = historyManager.siteIcon(for: domain) }
    }
}
