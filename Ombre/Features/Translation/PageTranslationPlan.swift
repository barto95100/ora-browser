import Foundation

/// A piece of the page's text sent to the translator, named by `id`.
struct PageTextPiece: Equatable {
    let id: String
    let text: String
}

/// The page's text pieces, each different text translated once (menus and
/// buttons repeat), sent in small groups so that the first ones show within
/// a second or two: Apple's translation takes a fraction of a second per
/// piece, minutes for a whole page.
struct PageTranslationPlan {
    /// The different texts, in the page's order (the visible ones first).
    let texts: [String]
    /// For each text, where it is on the page (piece numbers).
    let positions: [[Int]]
    /// The groups sent one after the other, as ranges of `texts`.
    let groups: [Range<Int>]

    var pieceCount: Int {
        positions.reduce(0) { $0 + $1.count }
    }

    init(pieces: [String], maxPieces: Int = 12, maxCharacters: Int = 600) {
        var texts: [String] = []
        var positions: [[Int]] = []
        var indexOfText: [String: Int] = [:]
        for (position, piece) in pieces.enumerated() where !piece.isEmpty {
            if let index = indexOfText[piece] {
                positions[index].append(position)
            } else {
                indexOfText[piece] = texts.count
                texts.append(piece)
                positions.append([position])
            }
        }
        var groups: [Range<Int>] = []
        var start = 0
        var characters = 0
        for (index, text) in texts.enumerated() {
            let isFull = index - start >= maxPieces || (characters > 0 && characters + text.count > maxCharacters)
            if isFull {
                groups.append(start ..< index)
                start = index
                characters = 0
            }
            characters += text.count
        }
        if start < texts.count { groups.append(start ..< texts.count) }
        self.texts = texts
        self.positions = positions
        self.groups = groups
    }

    func pieces(of group: Range<Int>) -> [PageTextPiece] {
        group.map { PageTextPiece(id: String($0), text: texts[$0]) }
    }

    /// Translations by text number, as translations by piece number (what
    /// the page's script applies).
    func pageTranslations(_ translations: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, translated) in translations {
            guard let index = Int(key), positions.indices.contains(index) else { continue }
            for position in positions[index] {
                result[String(position)] = translated
            }
        }
        return result
    }

    /// How many of the page's pieces the first `count` texts cover.
    func pieceCount(ofFirst count: Int) -> Int {
        positions.prefix(count).reduce(0) { $0 + $1.count }
    }
}
