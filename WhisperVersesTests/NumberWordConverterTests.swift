import XCTest
@testable import WhisperVerses

final class NumberWordConverterTests: XCTestCase {

    // MARK: - Single Words

    func testOnes() {
        XCTAssertEqual(NumberWordConverter.convert("one"), "1")
        XCTAssertEqual(NumberWordConverter.convert("nine"), "9")
        XCTAssertEqual(NumberWordConverter.convert("zero"), "0")
    }

    func testTeens() {
        XCTAssertEqual(NumberWordConverter.convert("ten"), "10")
        XCTAssertEqual(NumberWordConverter.convert("sixteen"), "16")
        XCTAssertEqual(NumberWordConverter.convert("nineteen"), "19")
    }

    func testTens() {
        XCTAssertEqual(NumberWordConverter.convert("twenty"), "20")
        XCTAssertEqual(NumberWordConverter.convert("ninety"), "90")
    }

    func testOrdinals() {
        XCTAssertEqual(NumberWordConverter.convert("first"), "1")
        XCTAssertEqual(NumberWordConverter.convert("second"), "2")
        XCTAssertEqual(NumberWordConverter.convert("third"), "3")
        XCTAssertEqual(NumberWordConverter.convert("fourth"), "4")
        XCTAssertEqual(NumberWordConverter.convert("fifth"), "5")
        XCTAssertEqual(NumberWordConverter.convert("ninth"), "9")
        XCTAssertEqual(NumberWordConverter.convert("tenth"), "10")
        XCTAssertEqual(NumberWordConverter.convert("sixteenth"), "16")
        XCTAssertEqual(NumberWordConverter.convert("nineteenth"), "19")
        XCTAssertEqual(NumberWordConverter.convert("twentieth"), "20")
        XCTAssertEqual(NumberWordConverter.convert("ninetieth"), "90")
    }

    func testCompoundOrdinals() {
        XCTAssertEqual(NumberWordConverter.convert("twenty-first"), "21")
        XCTAssertEqual(NumberWordConverter.convert("twenty first"), "21")
        XCTAssertEqual(NumberWordConverter.convert("thirty-second"), "32")
        XCTAssertEqual(NumberWordConverter.convert("ninety-ninth"), "99")
    }

    // MARK: - Multi-Word Numbers

    func testTwoWordNumbers() {
        XCTAssertEqual(NumberWordConverter.convert("twenty eight"), "28")
        XCTAssertEqual(NumberWordConverter.convert("thirty one"), "31")
        XCTAssertEqual(NumberWordConverter.convert("ninety nine"), "99")
    }

    func testHyphenated() {
        XCTAssertEqual(NumberWordConverter.convert("twenty-eight"), "28")
        XCTAssertEqual(NumberWordConverter.convert("forty-two"), "42")
    }

    func testHundreds() {
        XCTAssertEqual(NumberWordConverter.convert("one hundred"), "100")
        XCTAssertEqual(NumberWordConverter.convert("one hundred and forty three"), "143")
        XCTAssertEqual(NumberWordConverter.convert("two hundred"), "200")
        XCTAssertEqual(NumberWordConverter.convert("one hundred and three"), "103")
        XCTAssertEqual(NumberWordConverter.convert("a hundred"), "100")
        XCTAssertEqual(NumberWordConverter.convert("a hundred and three"), "103")
        XCTAssertEqual(NumberWordConverter.convert("a hundred and twenty one"), "121")
    }

    func testHundredsWithOrdinals() {
        XCTAssertEqual(NumberWordConverter.convert("one hundred and third"), "103")
        XCTAssertEqual(NumberWordConverter.convert("one hundred and twenty-first"), "121")
        XCTAssertEqual(NumberWordConverter.convert("a hundred and fifth"), "105")
    }

    // MARK: - Passthrough & Invalid

    func testAlreadyDigits() {
        XCTAssertEqual(NumberWordConverter.convert("42"), "42")
        XCTAssertEqual(NumberWordConverter.convert("3"), "3")
    }

    func testInvalidInput() {
        XCTAssertNil(NumberWordConverter.convert("hello"))
        XCTAssertNil(NumberWordConverter.convert(""))
        XCTAssertNil(NumberWordConverter.convert("the"))
    }

    func testCaseInsensitive() {
        XCTAssertEqual(NumberWordConverter.convert("Sixteen"), "16")
        XCTAssertEqual(NumberWordConverter.convert("TWENTY"), "20")
    }

    // MARK: - replaceNumberWordsInText

    func testReplaceInText() {
        XCTAssertEqual(
            NumberWordConverter.replaceNumberWordsInText("John three sixteen"),
            "John 3 16"
        )
    }

    func testReplacePreservesNonNumbers() {
        let result = NumberWordConverter.replaceNumberWordsInText("turn to Romans eight")
        XCTAssertEqual(result, "turn to Romans 8")
    }

    func testReplacePreservesTrailingPunctuation() {
        let result = NumberWordConverter.replaceNumberWordsInText("three, four")
        XCTAssertEqual(result, "3, 4")
    }

    func testReplaceMultiWord() {
        let result = NumberWordConverter.replaceNumberWordsInText("one hundred and fifty three verses")
        XCTAssertEqual(result, "153 verses")
    }
}
