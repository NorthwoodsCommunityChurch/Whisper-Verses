import Foundation
import os.log

private let logger = Logger(subsystem: "com.whisperverses", category: "BibleBookIndex")

struct BibleBook: Codable, Identifiable {
    var id: String { code }
    let code: String           // USX code: "GEN", "EXO", etc.
    let name: String           // Full name: "Genesis"
    let aliases: [String]      // ["gen", "ge"]
    let chapters: [Int]        // Verse counts per chapter: [31, 25, 24, ...] (index 0 = chapter 1)

    var totalVerses: Int {
        chapters.reduce(0, +)
    }

    var chapterCount: Int {
        chapters.count
    }

    func verseCount(forChapter chapter: Int) -> Int? {
        guard chapter >= 1 && chapter <= chapters.count else { return nil }
        return chapters[chapter - 1]
    }

    func isValid(chapter: Int, verse: Int) -> Bool {
        guard let count = verseCount(forChapter: chapter) else { return false }
        return verse >= 1 && verse <= count
    }
}

struct BibleBookIndex {
    let books: [BibleBook]
    private let nameMap: [String: BibleBook]

    init(books: [BibleBook]) {
        self.books = books
        var map: [String: BibleBook] = [:]
        for book in books {
            map[book.name.lowercased()] = book
            map[book.code.lowercased()] = book
            for alias in book.aliases {
                map[alias.lowercased()] = book
            }
        }
        self.nameMap = map
    }

    func lookup(_ name: String) -> BibleBook? {
        nameMap[name.lowercased()]
    }

    static func load() -> BibleBookIndex {
        guard let url = Bundle.main.url(forResource: "BibleBooks", withExtension: "json") else {
            logger.error("BibleBookIndex.load: ERROR - BibleBooks.json not found in bundle")
            return BibleBookIndex(books: [])
        }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("BibleBookIndex.load: ERROR - Could not read BibleBooks.json")
            return BibleBookIndex(books: [])
        }
        guard let books = try? JSONDecoder().decode([BibleBook].self, from: data) else {
            logger.error("BibleBookIndex.load: ERROR - Could not decode BibleBooks.json")
            return BibleBookIndex(books: [])
        }

        // Validate Psalms specifically (debugging Psalms 150:6 issue)
        if let psalms = books.first(where: { $0.code == "PSA" }) {
            logger.info("BibleBookIndex.load: Psalms loaded with \(psalms.chapters.count) chapters, last chapter has \(psalms.chapters.last ?? 0) verses")
        } else {
            logger.warning("BibleBookIndex.load: WARNING - Psalms (PSA) not found in loaded books!")
        }

        logger.info("BibleBookIndex.load: Loaded \(books.count) books")
        return BibleBookIndex(books: books)
    }
}
