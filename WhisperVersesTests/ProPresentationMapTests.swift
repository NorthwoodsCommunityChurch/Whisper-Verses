import XCTest
@testable import WhisperVerses

final class ProPresentationMapTests: XCTestCase {

    // MARK: - Registration & Lookup

    func testRegisterAndLookup() {
        var map = ProPresentationMap()
        // John: chapter 1 = 51 verses, chapter 2 = 25 verses, chapter 3 = 36 verses
        map.register(
            bookCode: "JHN",
            presentationUUID: "john-uuid",
            chapters: [51, 25, 36, 54, 47, 71, 53, 59, 41, 42, 57, 50, 38, 31, 27, 33, 26, 40, 42, 31, 25]
        )

        let ref = BibleReference(bookCode: "JHN", bookName: "John", chapter: 3, verseStart: 16)
        let location = map.lookup(ref)

        XCTAssertNotNil(location)
        XCTAssertEqual(location?.presentationUUID, "john-uuid")
        // Slide index = ch1(51) + ch2(25) + (16-1) = 91
        XCTAssertEqual(location?.slideIndex, 91)
    }

    func testFirstVerse() {
        var map = ProPresentationMap()
        map.register(bookCode: "GEN", presentationUUID: "gen-uuid", chapters: [31, 25])

        let ref = BibleReference(bookCode: "GEN", bookName: "Genesis", chapter: 1, verseStart: 1)
        let location = map.lookup(ref)

        XCTAssertEqual(location?.slideIndex, 0, "First verse of first chapter should be slide 0")
    }

    func testSecondChapterFirstVerse() {
        var map = ProPresentationMap()
        map.register(bookCode: "GEN", presentationUUID: "gen-uuid", chapters: [31, 25])

        let ref = BibleReference(bookCode: "GEN", bookName: "Genesis", chapter: 2, verseStart: 1)
        let location = map.lookup(ref)

        XCTAssertEqual(location?.slideIndex, 31, "First verse of ch2 should equal ch1 verse count")
    }

    // MARK: - Not Found Cases

    func testUnknownBookReturnsNil() {
        let map = ProPresentationMap()
        let ref = BibleReference(bookCode: "XXX", bookName: "Unknown", chapter: 1, verseStart: 1)
        XCTAssertNil(map.lookup(ref))
    }

    func testInvalidChapterReturnsNil() {
        var map = ProPresentationMap()
        map.register(bookCode: "JUD", presentationUUID: "jude-uuid", chapters: [25])

        let ref = BibleReference(bookCode: "JUD", bookName: "Jude", chapter: 2, verseStart: 1)
        XCTAssertNil(map.lookup(ref), "Jude only has 1 chapter")
    }

    func testInvalidVerseReturnsNil() {
        var map = ProPresentationMap()
        map.register(bookCode: "JUD", presentationUUID: "jude-uuid", chapters: [25])

        let ref = BibleReference(bookCode: "JUD", bookName: "Jude", chapter: 1, verseStart: 26)
        XCTAssertNil(map.lookup(ref), "Jude 1 only has 25 verses")
    }

    // MARK: - State Queries

    func testIsEmpty() {
        let map = ProPresentationMap()
        XCTAssertTrue(map.isEmpty)
        XCTAssertEqual(map.count, 0)
    }

    func testHasBook() {
        var map = ProPresentationMap()
        map.register(bookCode: "JHN", presentationUUID: "uuid", chapters: [51])

        XCTAssertTrue(map.hasBook("JHN"))
        XCTAssertFalse(map.hasBook("GEN"))
        XCTAssertEqual(map.count, 1)
    }

    // MARK: - Psalms 150:6 Specific Test

    func testPsalms150_6_WithRealData() {
        let bookIndex = TestHelpers.loadBookIndex()
        guard let psalms = bookIndex.lookup("PSA") else {
            XCTFail("Could not find Psalms in BibleBooks.json")
            return
        }

        // Verify the Psalms data
        XCTAssertEqual(psalms.code, "PSA")
        XCTAssertEqual(psalms.name, "Psalms")
        XCTAssertEqual(psalms.chapters.count, 150, "Psalms should have 150 chapters")
        XCTAssertEqual(psalms.chapters[149], 6, "Psalm 150 should have 6 verses")

        // Register Psalms with real chapter data
        var map = ProPresentationMap()
        map.register(
            bookCode: psalms.code,
            presentationUUID: "psalms-uuid",
            chapters: psalms.chapters
        )

        // Look up Psalms 150:6
        let ref = BibleReference(bookCode: "PSA", bookName: "Psalms", chapter: 150, verseStart: 6)
        let location = map.lookup(ref)

        XCTAssertNotNil(location, "Psalms 150:6 should be found")
        XCTAssertEqual(location?.presentationUUID, "psalms-uuid")

        // Calculate expected slide index: sum of all verses in chapters 1-149, plus verse offset (5)
        let expectedIndex = psalms.chapters.prefix(149).reduce(0, +) + 5
        XCTAssertEqual(location?.slideIndex, expectedIndex)

        // Also verify Psalms 150:6 is valid according to BibleBook
        XCTAssertTrue(psalms.isValid(chapter: 150, verse: 6), "Psalms 150:6 should be valid")
    }

    func testPsalms150_6_EdgeCases() {
        let bookIndex = TestHelpers.loadBookIndex()
        guard let psalms = bookIndex.lookup("PSA") else {
            XCTFail("Could not find Psalms in BibleBooks.json")
            return
        }

        var map = ProPresentationMap()
        map.register(
            bookCode: psalms.code,
            presentationUUID: "psalms-uuid",
            chapters: psalms.chapters
        )

        // Test edge: last verse of last chapter
        let lastVerse = BibleReference(bookCode: "PSA", bookName: "Psalms", chapter: 150, verseStart: 6)
        XCTAssertNotNil(map.lookup(lastVerse), "Last verse should be found")

        // Test edge: verse 7 in chapter 150 (doesn't exist)
        let invalidVerse = BibleReference(bookCode: "PSA", bookName: "Psalms", chapter: 150, verseStart: 7)
        XCTAssertNil(map.lookup(invalidVerse), "Verse 7 doesn't exist in Psalm 150")

        // Test edge: chapter 151 (doesn't exist)
        let invalidChapter = BibleReference(bookCode: "PSA", bookName: "Psalms", chapter: 151, verseStart: 1)
        XCTAssertNil(map.lookup(invalidChapter), "Chapter 151 doesn't exist in Psalms")
    }
}
