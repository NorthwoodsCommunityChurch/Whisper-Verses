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

    // MARK: - Comma Format (common transcription artifact)

    func testCommaFormat() {
        let verses = detector.detect(in: "Matthew 28, 19")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "MAT")
        XCTAssertEqual(verses.first?.reference.chapter, 28)
        XCTAssertEqual(verses.first?.reference.verseStart, 19)
    }

    func testCommaFormatNoSpace() {
        detector.clearHistory()
        let verses = detector.detect(in: "Matthew 28,19")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "MAT")
        XCTAssertEqual(verses.first?.reference.chapter, 28)
        XCTAssertEqual(verses.first?.reference.verseStart, 19)
    }

    func testCommaFormatInSentence() {
        detector.clearHistory()
        let verses = detector.detect(in: "he said this in Matthew 28, 19. So he says")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "MAT")
        XCTAssertEqual(verses.first?.reference.chapter, 28)
        XCTAssertEqual(verses.first?.reference.verseStart, 19)
    }

    // MARK: - "And" Format (spoken separator)

    func testAndFormat() {
        let verses = detector.detect(in: "Matthew 28 and 19")
        XCTAssertEqual(verses.count, 1)
        XCTAssertEqual(verses.first?.reference.bookCode, "MAT")
        XCTAssertEqual(verses.first?.reference.chapter, 28)
        XCTAssertEqual(verses.first?.reference.verseStart, 19)
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

    // MARK: - Repeated Detection (dedup removed — capture layer handles duplicates)

    func testRepeatedVerseStillDetected() {
        let first = detector.detect(in: "John 3:16")
        XCTAssertEqual(first.count, 1)

        // Same verse again should still be detected (capture layer filters duplicates)
        let second = detector.detect(in: "John 3:16")
        XCTAssertEqual(second.count, 1, "Repeated verse should still be detected")
    }

    func testPerSegmentDedup() {
        // Same verse twice in one segment should only detect once
        let verses = detector.detect(in: "John 3:16 is great, John 3:16 is important")
        XCTAssertEqual(verses.count, 1, "Same verse within one segment should deduplicate")
    }

    // MARK: - No False Positives

    func testNoDetectionInPlainText() {
        let verses = detector.detect(in: "the quick brown fox jumps over the lazy dog")
        XCTAssertEqual(verses.count, 0)
    }
}
