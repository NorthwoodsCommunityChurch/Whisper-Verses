import Foundation

/// Builds a mapping from Bible book codes to ProPresenter presentation UUIDs.
/// Queries Pro7 at startup to find all Bible presentations in the configured library,
/// parses their names (e.g., "Genesis 1_1-50_26 (KJV)") to identify books,
/// and registers them in the ProPresentationMap for on-the-fly slide index calculation.
@Observable
final class PresentationIndexer {
    var map = ProPresentationMap()
    var isIndexing = false
    var indexedBookCount = 0
    var errorMessage: String?

    private let api: ProPresenterAPI
    private let bookIndex: BibleBookIndex

    /// Regex to parse Pro7 presentation names like "Genesis 1_1-50_26 (KJV)".
    /// Captures everything before the verse range pattern as the book name.
    private let namePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(.+?)\s+\d+_\d+-\d+_\d+\s*\(.*\)$"#)
    }()

    init(api: ProPresenterAPI, bookIndex: BibleBookIndex = .load()) {
        self.api = api
        self.bookIndex = bookIndex
    }

    /// Index all Bible presentations in a Pro7 library.
    /// The libraryName should match the name of the library in Pro7 that contains
    /// Bible book presentations (e.g., "Bible KJV", "Default").
    func indexBiblePresentations(libraryName: String) async {
        await MainActor.run {
            isIndexing = true
            errorMessage = nil
            indexedBookCount = 0
            map = ProPresentationMap()
        }

        do {
            // 1. Find the library by name
            let libraries = try await api.getLibraries()
            guard let library = libraries.first(where: {
                $0.name.localizedCaseInsensitiveCompare(libraryName) == .orderedSame
            }) else {
                await setError("Library '\(libraryName)' not found. Available: \(libraries.map(\.name).joined(separator: ", "))")
                return
            }

            // 2. Get all presentations in that library
            let items = try await api.getLibraryItems(libraryId: library.uuid)

            // 3. Parse each presentation name and build the mapping
            let matcher = BookNameMatcher(bookIndex: bookIndex)
            var newMap = ProPresentationMap()
            var count = 0

            for item in items {
                guard let bookName = parseBookName(from: item.name) else { continue }

                // Look up the book using exact match first, then fuzzy
                guard let book = matcher.match(bookName) else {
                    print("PresentationIndexer: Could not match '\(bookName)' from '\(item.name)'")
                    continue
                }

                newMap.register(
                    bookCode: book.code,
                    presentationUUID: item.uuid,
                    chapters: book.chapters
                )
                count += 1
            }

            await MainActor.run {
                self.map = newMap
                self.indexedBookCount = count
                self.isIndexing = false
            }

            print("PresentationIndexer: Indexed \(count)/66 Bible books")

        } catch {
            await setError("Indexing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Name Parsing

    /// Parse a Pro7 presentation name to extract the Bible book name.
    /// "Genesis 1_1-50_26 (KJV)" → "Genesis"
    /// "1 Samuel 1_1-31_13 (KJV)" → "1 Samuel"
    /// "Song of Solomon 1_1-8_14 (KJV)" → "Song of Solomon"
    private func parseBookName(from presentationName: String) -> String? {
        let nsName = presentationName as NSString
        guard let match = namePattern?.firstMatch(
            in: presentationName,
            range: NSRange(location: 0, length: nsName.length)
        ) else { return nil }

        return nsName.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespaces)
    }

    private func setError(_ message: String) async {
        print("PresentationIndexer: \(message)")
        await MainActor.run {
            self.errorMessage = message
            self.isIndexing = false
        }
    }
}
