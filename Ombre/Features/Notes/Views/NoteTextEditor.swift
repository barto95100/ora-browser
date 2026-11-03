import AppKit
import SwiftUI

/// The editor of a note: plain Markdown, the images' lines small and faded
/// with space around them, so the text stays readable between captures.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.string = text
        Coordinator.style(textView)
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    /// The editor goes (read mode, another note): its undo steps go with it.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.undoManager.removeAllActions()
        (scrollView.documentView as? NSTextView)?.delegate = nil
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        // An image added, a box checked elsewhere: the caret stays put.
        let selection = textView.selectedRange()
        textView.string = text
        // Undoing would go back past a change made outside the editor.
        context.coordinator.undoManager.removeAllActions()
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        Coordinator.style(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// The editor's own undo steps. With the window's, ⌘Z after the
        /// editor was closed reached a text view gone, and crashed.
        let undoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            Self.style(textView)
        }

        private static let bodyFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        private static let imageFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        private static let headingFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        static func style(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            let imageParagraph = NSMutableParagraphStyle()
            imageParagraph.paragraphSpacingBefore = 6
            imageParagraph.paragraphSpacing = 6
            storage.beginEditing()
            storage.setAttributes([.font: bodyFont, .foregroundColor: NSColor.labelColor], range: all)
            (storage.string as NSString).enumerateSubstrings(in: all, options: .byLines) { line, range, _, _ in
                let trimmed = line?.trimmingCharacters(in: .whitespaces) ?? ""
                if trimmed.hasPrefix("![") || trimmed.hasPrefix("[![") {
                    storage.addAttributes([
                        .font: imageFont,
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: imageParagraph
                    ], range: range)
                } else if trimmed.hasPrefix("#") {
                    storage.addAttribute(.font, value: headingFont, range: range)
                }
            }
            storage.endEditing()
            textView.typingAttributes = [.font: bodyFont, .foregroundColor: NSColor.labelColor]
        }
    }
}
