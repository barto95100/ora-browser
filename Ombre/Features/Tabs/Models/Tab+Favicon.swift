import Foundation

@MainActor
extension Tab {
    /// Shows the icon the page declares, like Safari (from the page script).
    /// `certificateExceptions`: those of the page that sent the icons.
    func updateFavicon(
        from message: PageFaviconMessage,
        pageURL: URL?,
        certificateExceptions exceptions: [String: String] = [:]
    ) {
        guard let pageURL, let host = pageURL.host else { return }

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
        // Certificates the user accepted for this page (Continue anyway):
        // its icons too, with those certificates only.
        Task { [weak self] in
            let icon = await FaviconStore.shared.firstAvailableIcon(
                among: iconURLs, isPrivate: isPrivate, certificateExceptions: exceptions
            )
            // The tab may have moved to another site meanwhile.
            guard let self, faviconSiteHost == host else { return }
            favicon = icon?.icon
            faviconLocalFile = icon?.file
        }
    }
}
