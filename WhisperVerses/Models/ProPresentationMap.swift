import Foundation
import os.log

private let logger = Logger(subsystem: "com.whisperverses", category: "ProPresentationMap")

/// Maps Bible book codes to ProPresenter presentation UUIDs and computes
/// slide indices on-the-fly using verse count data from BibleBooks.json.
///
/// Instead of pre-computing all ~31,000 verse→slide mappings, we store one entry
/// per Bible book (66 entries) and calculate the slide index when needed.
struct ProPresentationMap {

    struct BookEntry {
        let presentationUUID: String
        let bookCode: String
        let chapters: [Int]  // verse counts per chapter (index 0 = chapter 1)
    }

    struct SlideLocation {
        let presentationUUID: String
        let slideIndex: Int
    }

    private var bookEntries: [String: BookEntry] = [:]  // bookCode → entry

    /// Register a Bible book with its Pro7 presentation UUID and verse count data.
    mutating func register(bookCode: String, presentationUUID: String, chapters: [Int]) {
        bookEntries[bookCode] = BookEntry(
            presentationUUID: presentationUUID,
            bookCode: bookCode,
            chapters: chapters
        )
    }

    /// Look up the Pro7 presentation UUID and slide index for a verse reference.
    /// Slide index is calculated as: sum of verses in all preceding chapters + (verse - 1).
    /// e.g., John 3:16 → chapters[0..1] = 51+25 = 76, verse offset = 15, slide = 91.
    func lookup(_ reference: BibleReference) -> SlideLocation? {
        guard let entry = bookEntries[reference.bookCode] else {
            logger.error("ProPresentationMap.lookup: FAILED - No entry for bookCode '\(reference.bookCode)'")
            logger.error("  - Requested: \(reference.bookCode) \(reference.chapter):\(reference.verseStart)")
            logger.error("  - Available bookCodes (\(bookEntries.count)): \(bookEntries.keys.sorted().joined(separator: ", "))")
            return nil
        }

        let chapter = reference.chapter
        guard chapter >= 1 && chapter <= entry.chapters.count else {
            logger.error("ProPresentationMap.lookup: FAILED - Chapter out of range")
            logger.error("  - Requested: \(reference.bookCode) \(chapter):\(reference.verseStart)")
            logger.error("  - chapters.count: \(entry.chapters.count)")
            return nil
        }
        guard reference.verseStart >= 1 && reference.verseStart <= entry.chapters[chapter - 1] else {
            logger.error("ProPresentationMap.lookup: FAILED - Verse out of range")
            logger.error("  - Requested: \(reference.bookCode) \(chapter):\(reference.verseStart)")
            logger.error("  - Max verse for chapter \(chapter): \(entry.chapters[chapter - 1])")
            return nil
        }

        // Sum verses in all chapters before the target chapter
        var slideIndex = 0
        for c in 0..<(chapter - 1) {
            slideIndex += entry.chapters[c]
        }
        // Add the verse offset within the chapter (0-based)
        slideIndex += reference.verseStart - 1

        return SlideLocation(presentationUUID: entry.presentationUUID, slideIndex: slideIndex)
    }

    /// Reverse-lookup: given a presentation UUID and slide index, return the verse reference string.
    /// e.g., presentationUUID for Matthew + slide 1069 → "Matthew 28:19"
    func verseLabel(presentationUUID: String, slideIndex: Int) -> String? {
        guard let entry = bookEntries.values.first(where: { $0.presentationUUID == presentationUUID }) else {
            return nil
        }

        // Walk chapters to find which chapter and verse this slide index maps to
        var remaining = slideIndex
        for (chapterIdx, verseCount) in entry.chapters.enumerated() {
            if remaining < verseCount {
                let chapter = chapterIdx + 1
                let verse = remaining + 1
                // Look up the book name from BibleBookIndex
                let bookIndex = BibleBookIndex.load()
                if let book = bookIndex.lookup(entry.bookCode) {
                    return "\(book.name) \(chapter):\(verse)"
                }
                return "\(entry.bookCode) \(chapter):\(verse)"
            }
            remaining -= verseCount
        }
        return nil
    }

    /// Check if a book is registered.
    func hasBook(_ bookCode: String) -> Bool {
        bookEntries[bookCode] != nil
    }

    var isEmpty: Bool { bookEntries.isEmpty }
    var count: Int { bookEntries.count }
}
