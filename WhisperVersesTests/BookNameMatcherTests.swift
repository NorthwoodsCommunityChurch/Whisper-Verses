import XCTest
@testable import WhisperVerses

final class BookNameMatcherTests: XCTestCase {
    var matcher: BookNameMatcher!

    override func setUp() {
        super.setUp()
        matcher = BookNameMatcher(bookIndex: TestHelpers.loadBookIndex())
    }

    // MARK: - Exact Match

    func testExactFullName() {
        let book = matcher.match("John")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "JHN")
    }

    func testExactAlias() {
        let book = matcher.match("jhn")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "JHN")
    }

    func testCaseInsensitive() {
        let book = matcher.match("GENESIS")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "GEN")
    }

    func testUSXCode() {
        let book = matcher.match("ROM")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "ROM")
    }

    // MARK: - Prefix Normalization

    func testFirstPrefix() {
        let book = matcher.match("First Corinthians")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "1CO")
    }

    func testSecondPrefix() {
        let book = matcher.match("Second Timothy")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "2TI")
    }

    func test1stPrefix() {
        let book = matcher.match("1st John")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "1JN")
    }

    // MARK: - Fuzzy Matching

    func testFuzzyOneCharOff() {
        // "Genesiss" is one edit away from "Genesis"
        let book = matcher.match("Genesiss")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "GEN")
    }

    func testFuzzyRevelations() {
        // Common misspelling
        let book = matcher.match("Revelations")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.code, "REV")
    }

    // MARK: - No Match

    func testNoMatchGarbage() {
        XCTAssertNil(matcher.match("xyzzy"))
    }

    func testNoMatchEmpty() {
        XCTAssertNil(matcher.match(""))
    }

    // MARK: - findAllOccurrences

    func testFindSingleOccurrence() {
        let occurrences = matcher.findAllOccurrences(in: "John 3:16")
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.book.code, "JHN")
    }

    func testFindMultipleOccurrences() {
        let occurrences = matcher.findAllOccurrences(in: "read John 3:16 and Romans 8:28")
        XCTAssertEqual(occurrences.count, 2)
        guard occurrences.count >= 2 else { return }
        XCTAssertEqual(occurrences[0].book.code, "JHN")
        XCTAssertEqual(occurrences[1].book.code, "ROM")
    }

    func testFindMultiWordBook() {
        let occurrences = matcher.findAllOccurrences(in: "1 Corinthians 13:4")
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.book.code, "1CO")
    }

    func testNoFalsePositivesOnCommonWords() {
        let occurrences = matcher.findAllOccurrences(in: "the quick brown fox")
        XCTAssertEqual(occurrences.count, 0)
    }
}
