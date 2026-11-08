import Foundation

/// A piece of the page's text sent to the translator, named by `id`.
struct PageTextPiece: Equatable {
    let id: String
    let text: String
}

/// The page's text pieces, each different text translated once (menus and
/// buttons repeat).
struct PageTranslationPlan {
    /// The different texts, in the page's order (the visible ones first).
    let texts: [String]
    /// For each text, where it is on the page (piece numbers).
    let positions: [[Int]]
    /// For each piece number, its text (nil for an empty piece).
    let textOfPiece: [Int?]

    var pieceCount: Int {
        positions.reduce(0) { $0 + $1.count }
    }

    init(pieces: [String]) {
        var texts: [String] = []
        var positions: [[Int]] = []
        var textOfPiece: [Int?] = Array(repeating: nil, count: pieces.count)
        var indexOfText: [String: Int] = [:]
        for (position, piece) in pieces.enumerated() where !piece.isEmpty {
            if let index = indexOfText[piece] {
                positions[index].append(position)
                textOfPiece[position] = index
            } else {
                indexOfText[piece] = texts.count
                textOfPiece[position] = texts.count
                texts.append(piece)
                positions.append([position])
            }
        }
        self.texts = texts
        self.positions = positions
        self.textOfPiece = textOfPiece
    }

    /// The texts numbered `indexes`, for the translator (named by number).
    func pieces(of indexes: [Int]) -> [PageTextPiece] {
        indexes.map { PageTextPiece(id: String($0), text: texts[$0]) }
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
}

/// The texts still to translate, sent in small groups: Apple's translation
/// takes about a second for 130 characters (measured on spiegel.de, German
/// into French: 3½ minutes for the whole page, the same in one batch, in
/// parallel sessions or with longer requests). So what the user sees comes
/// first: the text on screen when the translation starts, then the text
/// scrolled to, then the rest in the page's order, without waiting.
struct PageTranslationQueue {
    let plan: PageTranslationPlan
    /// The first group: small, shown within a second.
    var firstGroup = (pieces: 4, characters: 300)
    var group = (pieces: 12, characters: 600)

    private var pending: [Int]
    private var isPending: [Bool]
    private var sentGroups = 0

    /// `done`: texts already translated (the page's memory).
    init(plan: PageTranslationPlan, done: Set<Int> = []) {
        self.plan = plan
        pending = plan.texts.indices.filter { !done.contains($0) }
        isPending = plan.texts.indices.map { !done.contains($0) }
    }

    var isEmpty: Bool {
        pending.isEmpty
    }

    /// The page's pieces already translated.
    var donePieces: Int {
        plan.positions.indices.reduce(0) { $0 + (isPending[$1] ? 0 : plan.positions[$1].count) }
    }

    /// The next group, taken from the queue: the texts of `onScreen` (piece
    /// numbers the user now sees) first, then the others in order.
    mutating func next(onScreen: [Int] = []) -> [Int] {
        let limit = sentGroups == 0 ? firstGroup : group
        sentGroups += 1
        var chosen: [Int] = []
        var characters = 0
        func take(_ text: Int) -> Bool {
            guard isPending[text], !chosen.contains(text) else { return true }
            let length = plan.texts[text].count
            if chosen.count >= limit.pieces || (!chosen.isEmpty && characters + length > limit.characters) {
                return false
            }
            chosen.append(text)
            characters += length
            return true
        }
        for piece in onScreen where plan.textOfPiece.indices.contains(piece) {
            guard let text = plan.textOfPiece[piece] else { continue }
            if !take(text) { break }
        }
        for text in pending where !take(text) {
            break
        }
        for text in chosen {
            isPending[text] = false
        }
        pending.removeAll { !isPending[$0] }
        return chosen
    }
}
