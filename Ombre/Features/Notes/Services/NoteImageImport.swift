import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Images the user brings to a note: a screenshot pasted (⌘⇧⌃4 copies one),
/// dropped (the screenshot thumbnail, a Finder file, an image of a page) or
/// chosen from a file. All become PNG files of the note's `attachments`.
enum NoteImageImport {
    static let dropTypes: [UTType] = [.fileURL, .image]

    /// Raster images only: text copied from some apps comes with a PDF too.
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")
    ]

    /// Whether ⌘V would paste an image rather than text. Screenshot tools
    /// (CleanShot, Clop…) put the file's path as text next to the image:
    /// the image wins.
    static func pasteboardHasImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        imageFile(in: pasteboard) != nil || pasteboard.availableType(from: imageTypes) != nil
    }

    static func pngData(from pasteboard: NSPasteboard = .general) -> Data? {
        if let url = imageFile(in: pasteboard) {
            return pngData(fromFile: url)
        }
        guard pasteboard.availableType(from: imageTypes) != nil,
              let image = NSImage(pasteboard: pasteboard)
        else { return nil }
        return pngData(from: image)
    }

    /// An image file copied: as a file, or as its path.
    private static func imageFile(in pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        if let url = urls.first(where: isImageFile) { return url }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("/") || text.hasPrefix("file://")
        else { return nil }
        let url = text.hasPrefix("file://") ? URL(string: text) : URL(fileURLWithPath: text)
        guard let url, isImageFile(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func pngData(fromFile url: URL) -> Data? {
        NSImage(contentsOf: url).flatMap(pngData(from:))
    }

    /// A page snapshot, at its full (Retina) resolution.
    static func pngData(fromSnapshot image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Images dropped, as PNG, on the main queue.
    static func load(_ providers: [NSItemProvider], completion: @escaping (Data) -> Void) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, isImageFile(url), let png = pngData(fromFile: url) else { return }
                    DispatchQueue.main.async { completion(png) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data), let png = pngData(from: image) else { return }
                    DispatchQueue.main.async { completion(png) }
                }
            }
        }
        return accepted
    }

    /// An image chosen in an open panel.
    static func choose(completion: @escaping (Data) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let png = pngData(fromFile: url) { completion(png) }
        }
    }

    /// Watches ⌘V with an image in the pasteboard, while `isActive` says the
    /// note is the target (not a web page); returns the monitor to remove.
    static func watchPaste(
        in window: NSWindow?,
        isActive: @escaping () -> Bool,
        paste: @escaping (Data) -> Void
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 9,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.window === (window ?? NSApp.keyWindow),
                  isActive(),
                  pasteboardHasImage(),
                  let png = pngData()
            else { return event }
            paste(png)
            return nil
        }
    }

    /// Whether the window's focus is a note's text (a `TextEditor`), not a
    /// field (search, address bar) nor a page.
    static func isEditingNoteText(in window: NSWindow?) -> Bool {
        guard let textView = (window ?? NSApp.keyWindow)?.firstResponder as? NSTextView else { return false }
        return !textView.isFieldEditor
    }
}

/// The image button of a note: capture of the page (when there is one),
/// image file, pasted image.
struct NoteAddImageMenu: View {
    var captureVisible: (() -> Void)?
    let add: (Data) -> Void

    var body: some View {
        Menu {
            if let captureVisible {
                Button("Capture Visible Page", action: captureVisible)
            }
            Button("Paste Image") {
                if let png = NoteImageImport.pngData() { add(png) }
            }
            .disabled(!NoteImageImport.pasteboardHasImage())
            Button("Choose Image…") {
                NoteImageImport.choose(completion: add)
            }
        } label: {
            Image(systemName: "photo.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add an Image")
    }
}
