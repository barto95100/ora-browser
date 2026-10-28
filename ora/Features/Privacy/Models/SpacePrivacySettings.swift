import Foundation

struct SpacePrivacySettings: Codable, Equatable, Hashable {
    var blockThirdPartyTrackers: Bool
    var blockFingerprinting: Bool
    var adBlock: SpaceAdBlockSettings
    var cookiesPolicy: CookiesPolicy
    /// Sites (registrable domains) where content rules do not apply, set from
    /// the shield of the address bar.
    var exemptSites: [String] = []

    init(
        blockThirdPartyTrackers: Bool = false,
        blockFingerprinting: Bool = true,
        adBlocking: Bool = false,
        adBlock: SpaceAdBlockSettings? = nil,
        cookiesPolicy: CookiesPolicy = .allowAll
    ) {
        self.blockThirdPartyTrackers = blockThirdPartyTrackers
        self.blockFingerprinting = blockFingerprinting
        self.adBlock = adBlock ?? SpaceAdBlockSettings(enabled: adBlocking)
        self.cookiesPolicy = cookiesPolicy
    }

    /// Whether ads or trackers are blocked.
    var hasProtections: Bool {
        adBlock.enabled || blockThirdPartyTrackers
    }

    /// Ads and trackers blocked with the recommended lists, others kept.
    mutating func turnOnRecommendedProtections() {
        blockThirdPartyTrackers = true
        adBlock.enabled = true
        for id in FilterListCatalogService.recommendedProtectionIDs where !adBlock.enabledBuiltinListIDs.contains(id) {
            adBlock.enabledBuiltinListIDs.append(id)
        }
    }

    var adBlocking: Bool {
        get { adBlock.enabled }
        set { adBlock.enabled = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case blockThirdPartyTrackers
        case blockFingerprinting
        case adBlocking
        case adBlock
        case cookiesPolicy
        case exemptSites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockThirdPartyTrackers = try container.decodeIfPresent(Bool.self, forKey: .blockThirdPartyTrackers) ?? false
        blockFingerprinting = try container.decodeIfPresent(Bool.self, forKey: .blockFingerprinting) ?? true
        cookiesPolicy = try container.decodeIfPresent(CookiesPolicy.self, forKey: .cookiesPolicy) ?? .allowAll
        exemptSites = try container.decodeIfPresent([String].self, forKey: .exemptSites) ?? []

        if let nestedAdBlock = try container.decodeIfPresent(SpaceAdBlockSettings.self, forKey: .adBlock) {
            adBlock = nestedAdBlock
        } else {
            let legacyAdBlocking = try container.decodeIfPresent(Bool.self, forKey: .adBlocking) ?? false
            adBlock = SpaceAdBlockSettings(enabled: legacyAdBlocking)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockThirdPartyTrackers, forKey: .blockThirdPartyTrackers)
        try container.encode(blockFingerprinting, forKey: .blockFingerprinting)
        try container.encode(adBlock, forKey: .adBlock)
        try container.encode(cookiesPolicy, forKey: .cookiesPolicy)
        try container.encode(exemptSites, forKey: .exemptSites)
    }
}
