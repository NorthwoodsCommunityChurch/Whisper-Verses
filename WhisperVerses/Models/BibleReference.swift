import Foundation

struct BibleReference: Identifiable, Hashable, Codable {
    let id: UUID
    let bookCode: String       // e.g., "GEN", "JHN", "REV"
    let bookName: String       // e.g., "Genesis", "John", "Revelation"
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int?         // nil for single verse

    init(bookCode: String, bookName: String, chapter: Int, verseStart: Int, verseEnd: Int? = nil) {
        self.id = UUID()
        self.bookCode = bookCode
        self.bookName = bookName
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
    }

    var displayString: String {
        if let end = verseEnd, end != verseStart {
            return "\(bookName) \(chapter):\(verseStart)-\(end)"
        }
        return "\(bookName) \(chapter):\(verseStart)"
    }

    var filenameString: String {
        let book = bookName.replacingOccurrences(of: " ", with: "_")
        if let end = verseEnd, end != verseStart {
            return "\(book)_\(chapter)_\(verseStart)-\(end)"
        }
        return "\(book)_\(chapter)_\(verseStart)"
    }
}
