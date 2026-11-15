import AppKit

/// A page's image as agents get it: a PNG, no wider than asked.
enum AgentImage {
    struct PNG {
        let data: Data
        let width: Int
        let height: Int
    }

    /// `image` in sRGB, scaled down to `maxWidth` pixels if wider.
    static func png(of image: NSImage, maxWidth: Int) -> PNG? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width > 0, source.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var width = source.width
        var height = source.height
        if width > maxWidth {
            height = max(1, height * maxWidth / width)
            width = maxWidth
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            // Pages are opaque: no alpha, a smaller PNG.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
        else { return nil }
        return PNG(data: data, width: width, height: height)
    }
}
