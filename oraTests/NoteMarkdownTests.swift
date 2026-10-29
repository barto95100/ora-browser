import Foundation
@testable import Ora
import Testing

struct NoteMarkdownTests {
    @Test func blocksAreRecognized() {
        let markdown = """
        # Title
        Some text
        on two lines

        - item
        1. first
        > quote
        ---
        - [ ] todo
        - [x] done
        """
        #expect(NoteMarkdown.blocks(markdown) == [
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Some text\non two lines"),
            .bullet(text: "item"),
            .numbered(number: "1", text: "first"),
            .quote(text: "quote"),
            .rule,
            .task(line: 8, isDone: false, text: "todo"),
            .task(line: 9, isDone: true, text: "done")
        ])
    }

    @Test func anImageAloneOnItsLineIsAnImage() {
        let line = NoteMarkdown.imageLine(alt: "Page [1]", path: "attachments/capture-1.png")
        #expect(line == "![Page [1](attachments/capture-1.png)")
        #expect(NoteMarkdown.blocks(line) == [.image(alt: "Page [1", path: "attachments/capture-1.png", link: nil)])
        #expect(NoteMarkdown.blocks("![Page](attachments/capture-1.png)") == [
            .image(alt: "Page", path: "attachments/capture-1.png", link: nil)
        ])
        #expect(NoteMarkdown.blocks("see ![Page](a.png) here") == [.paragraph(text: "see ![Page](a.png) here")])
    }

    @Test func aCaptureKeepsItsPage() throws {
        let page = try #require(URL(string: "https://example.com/a?b=1"))
        let line = NoteMarkdown.imageLine(alt: "Example", path: "attachments/c.png", link: page)
        #expect(line == "[![Example](attachments/c.png)](https://example.com/a?b=1)")
        #expect(NoteMarkdown.blocks(line) == [
            .image(alt: "Example", path: "attachments/c.png", link: "https://example.com/a?b=1")
        ])
    }

    @Test func addedBlocksAreSeparatedByABlankLine() {
        #expect(NoteMarkdown.appending("![](a.png)", to: "") == "![](a.png)\n")
        #expect(NoteMarkdown.appending("![](b.png)", to: "![](a.png)\n") == "![](a.png)\n\n![](b.png)\n")
        #expect(NoteMarkdown.appending("![](b.png)", to: "text") == "text\n\n![](b.png)\n")
        #expect(NoteMarkdown.appending("![](b.png)", to: "text\n\n\n") == "text\n\n![](b.png)\n")
    }

    @Test func codeKeepsItsLines() {
        let markdown = "```\n# not a title\n- not a list\n```"
        #expect(NoteMarkdown.blocks(markdown) == [.code(text: "# not a title\n- not a list")])
    }

    @Test func tasksAreFoundWithTheirLines() {
        let markdown = "Intro\n- [ ] buy milk\n  * [X] call Paul\n- not a task"
        #expect(NoteMarkdown.tasks(markdown) == [
            .init(line: 1, isDone: false, text: "buy milk"),
            .init(line: 2, isDone: true, text: "call Paul")
        ])
    }

    @Test func togglingATaskChangesOnlyItsLine() {
        let markdown = "- [ ] a\n- [x] b"
        #expect(NoteMarkdown.togglingTask(atLine: 0, in: markdown) == "- [x] a\n- [x] b")
        #expect(NoteMarkdown.togglingTask(atLine: 1, in: markdown) == "- [ ] a\n- [ ] b")
    }

    @Test func togglingANonTaskLineChangesNothing() {
        let markdown = "# Title\n- [ ] a"
        #expect(NoteMarkdown.togglingTask(atLine: 0, in: markdown) == markdown)
    }
}

struct NotesStoreNameTests {
    @Test func fileNamesAvoidSlashesAndColons() {
        #expect(NotesStore.fileName(from: " Plan: 2026/Q4 ", fallback: "x") == "Plan- 2026-Q4")
        #expect(NotesStore.fileName(from: "...", fallback: "Untitled") == "Untitled")
    }

    @Test func aNumberedFolderStillBelongsToItsSpace() {
        #expect(NotesStore.isFolderName("Work", for: "Work"))
        #expect(NotesStore.isFolderName("Work 2", for: "Work"))
        #expect(!NotesStore.isFolderName("Work stuff", for: "Work"))
        #expect(!NotesStore.isFolderName("Home", for: "Work"))
    }
}
