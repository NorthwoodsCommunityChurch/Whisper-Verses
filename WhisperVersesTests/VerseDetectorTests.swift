import XCTest
@testable import WhisperVerses

final class VerseDetectorTests: XCTestCase {
    var detector: VerseDetector!

    override func setUp() {
        super.setUp()
        let bookIndex = TestHelpers.loadBookIndex()
        detector = VerseDetector(bookIndex: bookIndex)
    }

    override func tearDown() {
        detector.clearHistory()
        super.tearDown()
    }

    // MARK: - Standard Colon Format

    func testColonFormat() {
        let verses = detector.detect(in: "turn to John 3:16")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "JHN")
        XCTAssertEqual(verses.first?.reference.chapter, 3)
        XCTAssertEqual(verses.first?.reference.verseStart, 16)
        XCTAssertEqual(verses.first?.confidence, .high)
    }

    func testColonFormatWithRange() {
        let verses = detector.detect(in: "Romans 8:28-30")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "ROM")
        XCTAssertEqual(verses.first?.reference.chapter, 8)
        XCTAssertEqual(verses.first?.reference.verseStart, 28)
        XCTAssertEqual(verses.first?.reference.verseEnd, 30)
    }

    // MARK: - Space Format

    func testSpaceFormat() {
        detector.clearHistory()
        let verses = detector.detect(in: "Genesis 1 1")
        XCTAssertGreaterThanOrEqual(verses.count, 1)
        if let verse = verses.first {
            XCTAssertEqual(verse.reference.bookCode, "GEN")
            XCTAssertEqual(verse.reference.chapter, 1)
            XCTAssertEqual(verse.reference.verseStart, 1)
        }
    }

    // MARK: - Single-Chapter Books

    func testSingleChapterBook() {
        let verses = detector.detect(in: "Jude 25")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "JUD")
        XCTAssertEqual(verses.first?.reference.chapter, 1)
        XCTAssertEqual(verses.first?.reference.verseStart, 25)
    }

    // MARK: - Numbered Book Names

    func testNumberedBookColon() {
        detector.clearHistory()
        let verses = detector.detect(in: "1 Corinthians 13:4")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "1CO")
        XCTAssertEqual(verses.first?.reference.chapter, 13)
        XCTAssertEqual(verses.first?.reference.verseStart, 4)
    }

    // MARK: - Multiple Verses in One Text

    func testMultipleVerses() {
        detector.clearHistory()
        let verses = detector.detect(in: "John 3:16 and Romans 8:28")
        XCTAssertEqual(verses.count, 2)
    }

    // MARK: - Invalid References

    func testInvalidChapter() {
        let verses = detector.detect(in: "John 100:1")
        XCTAssertEqual(verses.count, 0, "John only has 21 chapters")
    }

    func testInvalidVerse() {
        let verses = detector.detect(in: "John 3:999")
        XCTAssertEqual(verses.count, 0, "John 3 only has 36 verses")
    }

    // MARK: - Deduplication

    func testDeduplicationSuppressesRepeat() {
        let first = detector.detect(in: "John 3:16")
        XCTAssertEqual(first.count, 1)

        // Same verse again within 30s window should be suppressed
        let second = detector.detect(in: "John 3:16")
        XCTAssertEqual(second.count, 0, "Duplicate within dedup window should be suppressed")
    }

    func testClearHistoryResetsDedupe() {
        _ = detector.detect(in: "John 3:16")
        detector.clearHistory()
        let after = detector.detect(in: "John 3:16")
        XCTAssertEqual(after.count, 1, "After clearHistory, same verse should detect again")
    }

    // MARK: - No False Positives

    func testNoDetectionInPlainText() {
        let verses = detector.detect(in: "the quick brown fox jumps over the lazy dog")
        XCTAssertEqual(verses.count, 0)
    }
}
