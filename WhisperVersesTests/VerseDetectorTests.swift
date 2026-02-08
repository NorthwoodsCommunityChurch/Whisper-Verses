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

    // MARK: - Psalms 150:6 End-to-End Test

    /// This test simulates the exact runtime flow that was failing:
    /// 1. Transcript says "Psalm 150, verse 6" (singular "Psalm")
    /// 2. Pro7 presentation is named "Psalms 1_1-150_6 (NIV)" (plural "Psalms")
    /// 3. Both should resolve to the same book code "PSA"
    /// 4. The lookup should find the verse
    func testPsalms150_6_EndToEnd() {
        let bookIndex = TestHelpers.loadBookIndex()

        // Step 1: Simulate transcript detection with ORIGINAL input (not pre-normalized)
        // The VerseDetector normalizes internally, so pass the raw transcript
        let detectedVerses = detector.detect(in: "In Psalm 150, verse 6, it says,")

        XCTAssertEqual(detectedVerses.count, 1, "Should detect exactly one verse")
        guard let detected = detectedVerses.first else {
            XCTFail("No verse detected")
            return
        }

        XCTAssertEqual(detected.reference.bookCode, "PSA", "Should detect as Psalms (PSA)")
        XCTAssertEqual(detected.reference.chapter, 150, "Should be chapter 150")
        XCTAssertEqual(detected.reference.verseStart, 6, "Should be verse 6")

        // Step 2: Simulate Pro7 indexing
        // The Pro7 presentation is named "Psalms 1_1-150_6 (NIV)"
        // parseBookName extracts "Psalms"
        let matcher = BookNameMatcher(bookIndex: bookIndex)
        guard let matchedBook = matcher.match("Psalms") else {
            XCTFail("Could not match 'Psalms' to a book")
            return
        }

        XCTAssertEqual(matchedBook.code, "PSA", "Pro7 'Psalms' should also resolve to PSA")
        XCTAssertEqual(matchedBook.chapters.count, 150, "Psalms should have 150 chapters")
        XCTAssertEqual(matchedBook.chapters[149], 6, "Psalm 150 should have 6 verses")

        // Step 3: Register in ProPresentationMap (simulating indexer)
        var map = ProPresentationMap()
        map.register(
            bookCode: matchedBook.code,
            presentationUUID: "psalms-pro7-uuid",
            chapters: matchedBook.chapters
        )

        // Step 4: Look up the detected verse
        let location = map.lookup(detected.reference)

        XCTAssertNotNil(location, "Psalms 150:6 lookup should succeed!")
        XCTAssertEqual(location?.presentationUUID, "psalms-pro7-uuid")

        // Calculate expected slide index
        let expectedIndex = matchedBook.chapters.prefix(149).reduce(0, +) + 5  // chapters 1-149 sum + (6-1)
        XCTAssertEqual(location?.slideIndex, expectedIndex, "Slide index should be correct")
    }

    /// Test that "Psalm" (singular) and "Psalms" (plural) resolve to the same book
    func testPsalmSingularVsPlural() {
        let bookIndex = TestHelpers.loadBookIndex()
        let matcher = BookNameMatcher(bookIndex: bookIndex)

        let fromSingular = matcher.match("Psalm")
        let fromPlural = matcher.match("Psalms")

        XCTAssertNotNil(fromSingular, "'Psalm' should match a book")
        XCTAssertNotNil(fromPlural, "'Psalms' should match a book")
        XCTAssertEqual(fromSingular?.code, "PSA", "'Psalm' should resolve to PSA")
        XCTAssertEqual(fromPlural?.code, "PSA", "'Psalms' should resolve to PSA")
        XCTAssertEqual(fromSingular?.code, fromPlural?.code, "Both should resolve to the same book")
    }
}
