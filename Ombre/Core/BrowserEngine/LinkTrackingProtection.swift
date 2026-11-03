import Foundation

/// Link Tracking Protection, like Safari: the parameters that only identify
/// who clicked (ad and newsletter click IDs, campaign tags) are taken off the
/// address before the page loads. The page itself does not need them.
enum LinkTrackingProtection {
    /// Lowercased names. Campaign tags (`utm_…`) are matched by prefix.
    static let parameters: Set<String> = [
        // Google, Microsoft, Yandex, ad networks
        "gclid", "dclid", "gbraid", "wbraid", "gclsrc", "msclkid", "yclid", "_openstat",
        // Social networks
        "fbclid", "igshid", "igsh", "twclid", "ttclid", "li_fat_id", "srsltid",
        // Newsletters and marketing tools
        "mc_eid", "mc_cid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "vero_conv",
        "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "ck_subscriber_id", "_kx"
    ]

    /// The URL without its tracking parameters, or nil when it has none.
    static func cleaned(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty
        else { return nil }

        let kept = items.filter { !isTracking($0.name) }
        guard kept.count < items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }

    static func isTracking(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || parameters.contains(name)
    }
}
