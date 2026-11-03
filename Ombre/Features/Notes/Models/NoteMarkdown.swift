import Foundation

/// The Markdown of notes, read line by line: enough for the reading view
/// (titles, lists, tasks, quotes, code) and for tasks (`- [ ] …`).
enum NoteMarkdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        /// A `- [ ]` / `- [x]` item; `line` is its line in the note.
        case task(line: Int, isDone: Bool, text: String)
        case bullet(text: String)
        case numbered(number: String, text: String)
        case quote(text: String)
        case code(text: String)
        case rule
        /// `![alt](path)` alone on its line, `path` relative to the note; or
        /// `[![alt](path)](link)`: a capture with the page it was taken from.
        case image(alt: String, path: String, link: String?)
        case paragraph(text: String)
    }

    struct Task: Equatable {
        let line: Int
        let isDone: Bool
        let text: String
    }

    static func blocks(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func endParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(text: open.joined(separator: "\n")))
                    code = nil
                } else {
                    endParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            if trimmed.isEmpty {
                endParagraph()
                continue
            }
            if let task = task(in: line, at: index) {
                endParagraph()
                blocks.append(.task(line: index, isDone: task.isDone, text: task.text))
            } else if let image = image(trimmed) {
                endParagraph()
                blocks.append(image)
            } else if let heading = heading(trimmed) {
                endParagraph()
                blocks.append(heading)
            } else if trimmed == "---" || trimmed == "***" {
                endParagraph()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                endParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2))))
            } else if let numbered = numbered(trimmed) {
                endParagraph()
                blocks.append(numbered)
            } else if trimmed.hasPrefix(">") {
                endParagraph()
                blocks.append(.quote(text: trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let open = code {
            blocks.append(.code(text: open.joined(separator: "\n")))
        }
        endParagraph()
        return blocks
    }

    /// `block` at the end of the note, after a blank line: images added one
    /// after the other stay apart when the note is edited.
    static func appending(_ block: String, to markdown: String) -> String {
        var text = markdown
        while text.hasSuffix("\n\n") {
            text.removeLast()
        }
        if !text.isEmpty { text += text.hasSuffix("\n") ? "\n" : "\n\n" }
        return text + block + "\n"
    }

    /// The line of an image of the note's folder, linked to its page if any.
    static func imageLine(alt: String, path: String, link: URL? = nil) -> String {
        let image = "![\(alt.replacingOccurrences(of: "]", with: ""))](\(path))"
        return link.map { "[\(image)](\($0.absoluteString))" } ?? image
    }

    private static func image(_ trimmed: String) -> Block? {
        if trimmed.hasPrefix("[!["), trimmed.hasSuffix(")"),
           let middle = trimmed.range(of: ")](", options: .backwards)
        {
            let innerEnd = trimmed.index(after: middle.lowerBound)
            let inner = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< innerEnd])
            let link = String(trimmed[middle.upperBound ..< trimmed.index(before: trimmed.endIndex)])
            guard !link.isEmpty, case .image(let alt, let path, nil)? = image(inner) else { return nil }
            return .image(alt: alt, path: path, link: link)
        }
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")"),
              let middle = trimmed.range(of: "](")
        else { return nil }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2) ..< middle.lowerBound])
        let path = String(trimmed[middle.upperBound ..< trimmed.index(before: trimmed.endIndex)])
        guard !path.isEmpty, !alt.contains("]"), !path.contains("(") else { return nil }
        return .image(alt: alt, path: path, link: nil)
    }

    /// The note's tasks, done or not, in order.
    static func tasks(_ markdown: String) -> [Task] {
        markdown.components(separatedBy: "\n").enumerated().compactMap { task(in: $0.element, at: $0.offset) }
    }

    /// The note with the task of `line` checked or unchecked.
    static func togglingTask(atLine line: Int, in markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(line), let task = task(in: lines[line], at: line) else { return markdown }
        // Only the box, the first one of the line: the text may hold brackets too.
        let current = lines[line]
        let box = task.isDone ? "[x]" : "[ ]"
        guard let range = current.range(of: box, options: .caseInsensitive) else { return markdown }
        lines[line] = current.replacingCharacters(in: range, with: task.isDone ? "[ ]" : "[x]")
        return lines.joined(separator: "\n")
    }

    private static func task(in line: String, at index: Int) -> Task? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let rest = trimmed.dropFirst(marker.count)
            for (box, isDone) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(box) {
                return Task(line: index, isDone: isDone, text: String(rest.dropFirst(box.count)))
            }
        }
        return nil
    }

    private static func heading(_ line: String) -> Block? {
        let level = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(level), line.dropFirst(level).hasPrefix(" ") else { return nil }
        return .heading(level: level, text: line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func numbered(_ line: String) -> Block? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return .numbered(number: String(digits), text: String(line.dropFirst(digits.count + 2)))
    }
}
