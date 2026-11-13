import AppKit
import CoreImage
import FaviconFinder
import SwiftUI

@MainActor
final class FaviconService: ObservableObject {
    static let shared = FaviconService()
    /// Icons are shown at 16 to 32 points: kept at 32 (Retina), not at the
    /// site's largest (up to 512 px, about 1 MB each).
    static let iconSize: CGFloat = 32
    private var cache: [String: NSImage] = [:]
    private var colorCache: [String: Color] = [:]
    private var sourceURLCache: [String: URL] = [:]
    private var isFetching: Set<String> = []
    private var pendingCompletions: [String: [(NSImage?) -> Void]] = [:]

    func getFavicon(for searchURL: String) -> NSImage? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        if let cachedFavicon = cache[domain] {
            return cachedFavicon
        }

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    func getFaviconColor(for searchURL: String) -> Color? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        if let cachedColor = colorCache[domain] {
            return cachedColor
        }

        // If favicon exists but color doesn't, compute it
        if let favicon = cache[domain] {
            let color = Color(favicon.averageColor())
            colorCache[domain] = color
            return color
        }

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    /// The site's icon once found, or its HTTPS address meanwhile. None for a
    /// host on the local network (an IP address, `.local`…): it has no HTTPS on
    /// port 443, and asking each time the tab was drawn failed on its
    /// certificate; the page's own icon comes when it loads.
    func faviconURL(for domain: String) -> URL? {
        let normalizedDomain = normalizeDomain(domain)
        if let found = sourceURLCache[normalizedDomain] { return found }
        guard HTTPSUpgradePolicy.isPublic(normalizedDomain) else { return nil }
        return canonicalURL(for: normalizedDomain)
    }

    func faviconURL(forSearchURL searchURL: String) -> URL? {
        guard let domain = extractDomain(from: searchURL) else { return nil }
        return canonicalURL(for: domain)
    }

    private func extractDomain(from searchURL: String) -> String? {
        let trimmed = searchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed.replacingOccurrences(of: "{query}", with: "")

        if let host = URL(string: sanitized)?.host {
            return normalizeDomain(host)
        }

        if let host = URL(string: "https://\(sanitized)")?.host {
            return normalizeDomain(host)
        }

        return nil
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lowercased = domain.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private func canonicalURL(for domain: String) -> URL? {
        guard !domain.isEmpty else { return nil }
        return URL(string: "https://\(domain)")
    }

    func fetchFaviconSync(for searchURL: String, completion: @escaping (NSImage?) -> Void) {
        guard let domain = extractDomain(from: searchURL) else {
            completion(nil)
            return
        }
        if let cachedFavicon = cache[domain] {
            completion(cachedFavicon)
            return
        }
        fetchAndCacheFavicon(for: domain, completion: completion)
    }

    private func fetchAndCacheFavicon(for domain: String, completion: ((NSImage?) -> Void)? = nil) {
        if let cachedFavicon = cache[domain] {
            completion?(cachedFavicon)
            return
        }

        if let completion {
            pendingCompletions[domain, default: []].append(completion)
        }

        guard !isFetching.contains(domain) else { return }
        isFetching.insert(domain)

        // On the main thread, which owns the caches (the download itself
        // doesn't block it).
        Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            let payload = await self.fetchFaviconPayload(for: domain)
            await MainActor.run {
                self.completeFetch(
                    for: domain,
                    favicon: payload?.image,
                    sourceURL: payload?.sourceURL
                )
            }
        }
    }

    @MainActor
    private func completeFetch(for domain: String, favicon: NSImage?, sourceURL: URL?) {
        if let favicon = favicon.map({ $0.downscaled(toFit: Self.iconSize) }) {
            cache[domain] = favicon
            colorCache[domain] = Color(favicon.averageColor())
            if let sourceURL {
                sourceURLCache[domain] = sourceURL
            }
            objectWillChange.send()
        }

        isFetching.remove(domain)
        let completions = pendingCompletions.removeValue(forKey: domain) ?? []
        for completion in completions {
            completion(favicon)
        }
    }

    private func fetchFaviconPayload(for domain: String) async -> (image: NSImage, data: Data, sourceURL: URL)? {
        guard let siteURL = canonicalURL(for: domain) else { return nil }

        do {
            let favicon = try await FaviconFinder(url: siteURL)
                .fetchFaviconURLs()
                .download()
                .largest()
            guard let faviconImage = favicon.image else { return nil }
            return (faviconImage.image, faviconImage.data, favicon.url.source)
        } catch {
            return nil
        }
    }
}

extension NSImage {
    /// A copy at most `side` points wide and high, drawn at 2× (Retina); the
    /// image itself when already that small.
    func downscaled(toFit side: CGFloat) -> NSImage {
        guard size.width > side || size.height > side, size.width > 0, size.height > 0 else { return self }
        let scale = side / max(size.width, size.height)
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width * 2), pixelsHigh: Int(target.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return self }
        bitmap.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: target)
        image.addRepresentation(bitmap)
        return image
    }

    func averageColor() -> NSColor {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSColor.gray
        }

        let inputImage = CIImage(cgImage: cgImage)
        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )

        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]
        ) else {
            return NSColor.gray
        }

        guard let outputImage = filter.outputImage else {
            return NSColor.gray
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }
}
