import XCTest
@testable import WhisperVerses

final class SpokenFormNormalizerTests: XCTestCase {
    let normalizer = SpokenFormNormalizer()

    // MARK: - Chapter + Verse Patterns

    func testChapterVerseSpoken() {
        let result = normalizer.normalize("John chapter three verse sixteen")
        XCTAssertTrue(result.contains("3:16"), "Expected '3:16' in '\(result)'")
    }

    func testChapterVerseRange() {
        let result = normalizer.normalize("Romans chapter eight verses twenty eight through thirty")
        XCTAssertTrue(result.contains("8:28-30"), "Expected '8:28-30' in '\(result)'")
    }

    func testChapterVerseWithComma() {
        let result = normalizer.normalize("John chapter three, verse sixteen")
        XCTAssertTrue(result.contains("3:16"), "Expected '3:16' in '\(result)'")
    }

    // MARK: - Verse-Only Patterns

    func testVerseRange() {
        let result = normalizer.normalize("verses four through seven")
        XCTAssertTrue(result.contains("4-7"), "Expected '4-7' in '\(result)'")
    }

    func testVerseOnly() {
        let result = normalizer.normalize("verse twenty five")
        XCTAssertTrue(result.contains("25"), "Expected '25' in '\(result)'")
    }

    // MARK: - Book Of Prefix

    func testStripBookOf() {
        let result = normalizer.normalize("the book of Romans")
        XCTAssertTrue(result.contains("Romans"), "Expected 'Romans' in '\(result)'")
        XCTAssertFalse(result.contains("the book of"), "Should strip 'the book of'")
    }

    // MARK: - Number Word Replacement

    func testNumberWordsReplaced() {
        let result = normalizer.normalize("Romans eight twenty eight")
        // After normalization, number words should be digits
        XCTAssertTrue(result.contains("8"), "Expected '8' in '\(result)'")
        XCTAssertTrue(result.contains("28"), "Expected '28' in '\(result)'")
    }

    // MARK: - Through/To Conversion

    func testThroughBetweenDigits() {
        let result = normalizer.normalize("14 through 18")
        XCTAssertTrue(result.contains("14-18"), "Expected '14-18' in '\(result)'")
    }

    func testToBetweenDigits() {
        let result = normalizer.normalize("3 to 7")
        XCTAssertTrue(result.contains("3-7"), "Expected '3-7' in '\(result)'")
    }

    // MARK: - Passthrough

    func testAlreadyStandardForm() {
        let result = normalizer.normalize("John 3:16")
        XCTAssertTrue(result.contains("John"), "Expected 'John' in '\(result)'")
        XCTAssertTrue(result.contains("3:16"), "Expected '3:16' in '\(result)'")
    }

    func testPlainTextUnchanged() {
        let result = normalizer.normalize("and he said to them")
        XCTAssertEqual(result, "and he said to them")
    }

    // MARK: - Psalms 150:6 Exact Transcript Test

    func testPsalm150Verse6Transcript() {
        // Exact transcript from the failing case
        let result = normalizer.normalize("In Psalm 150, verse 6, it says,")
        print("Normalized: '\(result)'")
        // "verse 6" should be converted to just "6"
        XCTAssertTrue(result.contains("150"), "Should contain 150")
        XCTAssertTrue(result.contains("6"), "Should contain 6")
        XCTAssertFalse(result.contains("verse"), "Should have removed 'verse'")
        // Expected result: "In Psalm 150, 6, it says,"
    }
}
