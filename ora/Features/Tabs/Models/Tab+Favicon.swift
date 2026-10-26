import Foundation

@MainActor
extension Tab {
    /// Shows the icon the page declares, like Safari (from the page script).
    func updateFavicon(from message: PageFaviconMessage) {
        guard let pageURL = URL(string: message.page), let host = pageURL.host else { return }

        // Another site: don't keep showing the previous site's icon meanwhile.
        if faviconSiteHost != host {
            faviconSiteHost = host
            faviconLocalFile = nil
        }

        let iconURLs = PageFaviconSelector.orderedIconURLs(from: message.icons, pageURL: pageURL)
        if let favicon, favicon == iconURLs.first, faviconLocalFile != nil {
            return // Already showing the page's best icon.
        }

        let isPrivate = isPrivate
        Task { [weak self] in
            let icon = await FaviconStore.shared.firstAvailableIcon(among: iconURLs, isPrivate: isPrivate)
            // The tab may have moved to another site meanwhile.
            guard let self, faviconSiteHost == host else { return }
            favicon = icon?.icon
            faviconLocalFile = icon?.file
        }
    }
}
