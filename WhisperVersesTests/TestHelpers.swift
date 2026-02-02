import Foundation
@testable import WhisperVerses

/// Shared helper for loading BibleBookIndex from the test bundle or source directory.
final class TestHelpers {
    static func loadBookIndex() -> BibleBookIndex {
        // Try test bundle first
        let testBundle = Bundle(for: TestHelpers.self)
        if let url = testBundle.url(forResource: "BibleBooks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let books = try? JSONDecoder().decode([BibleBook].self, from: data) {
            return BibleBookIndex(books: books)
        }

        // Try main bundle (app bundle loaded during tests)
        if let url = Bundle.main.url(forResource: "BibleBooks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let books = try? JSONDecoder().decode([BibleBook].self, from: data) {
            return BibleBookIndex(books: books)
        }

        // Fallback: resolve relative to source file location
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WhisperVersesTests/
            .deletingLastPathComponent()  // project root
        let resourceURL = sourceDir.appendingPathComponent("WhisperVerses/Resources/BibleBooks.json")
        if let data = try? Data(contentsOf: resourceURL),
           let books = try? JSONDecoder().decode([BibleBook].self, from: data) {
            return BibleBookIndex(books: books)
        }

        print("TestHelpers: WARNING - Could not load BibleBooks.json from any location")
        return BibleBookIndex(books: [])
    }
}
