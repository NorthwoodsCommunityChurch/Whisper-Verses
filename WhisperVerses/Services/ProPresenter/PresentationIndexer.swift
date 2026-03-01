import Foundation
import os.log

private let logger = Logger(subsystem: "com.whisperverses", category: "PresentationIndexer")

/// Builds a mapping from Bible verse references to ProPresenter slide locations.
/// Queries Pro7 to find all Bible presentations in the configured library.
///
/// Uses lazy loading: initial indexing only stores book→UUID mappings (fast).
/// Slide labels are fetched on-demand when a verse from that book is first looked up.
@Observable
final class PresentationIndexer {
    var map = ProPresentationMap()
    var isIndexing = false
    var indexedBookCount = 0
    var indexedVerseCount = 0
    var errorMessage: String?

    /// Track which book is currently being loaded (for UI feedback)
    var currentlyLoadingBook: String?

    private let api: ProPresenterAPI
    private let bookIndex: BibleBookIndex

    /// Returns the list of Bible books that are NOT indexed from Pro7.
    var missingBooks: [BibleBook] {
        bookIndex.books.filter { !map.hasBook($0.code) }
    }

    /// Regex to parse Pro7 presentation names like "Genesis 1_1-50_26 (KJV)" or "Jude 1_1-25 (NIV)".
    /// Captures everything before the verse range pattern as the book name.
    /// Handles both multi-chapter (1_1-50_26) and single-chapter (1_1-25) formats.
    private let namePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(.+?)\s+\d+_\d+-\d+(?:_\d+)?\s*\(.*\)$"#)
    }()

    init(api: ProPresenterAPI, bookIndex: BibleBookIndex = .load()) {
        self.api = api
        self.bookIndex = bookIndex
    }

    /// Index all Bible presentations in a Pro7 library.
    /// Only stores book→UUID mappings (fast). Slides are loaded lazily on first lookup.
    func indexBiblePresentations(libraryName: String) async {
        await MainActor.run {
            isIndexing = true
            errorMessage = nil
            indexedBookCount = 0
            indexedVerseCount = 0
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

            // 3. Parse each presentation and register book→UUID only (fast, no slide fetching)
            let matcher = BookNameMatcher(bookIndex: bookIndex)
            var newMap = ProPresentationMap()
            var bookCount = 0

            logger.info("PresentationIndexer: Processing \(items.count) items from library '\(libraryName)'")

            for item in items {
                guard let bookName = parseBookName(from: item.name) else {
                    logger.debug("PresentationIndexer: SKIPPED '\(item.name)' - could not parse book name")
                    continue
                }

                // Look up the book using exact match first, then fuzzy
                guard let book = matcher.match(bookName) else {
                    logger.warning("PresentationIndexer: SKIPPED '\(item.name)' - no match for '\(bookName)'")
                    continue
                }

                // Warn if overwriting an existing book (duplicate detection)
                if newMap.hasBook(book.code) {
                    logger.warning("PresentationIndexer: WARNING - Overwriting '\(book.code)' with '\(item.name)'")
                }

                // Just register the book→UUID mapping (no slide fetching)
                newMap.registerBook(bookCode: book.code, presentationUUID: item.uuid)
                bookCount += 1

                logger.info("PresentationIndexer: Registered \(book.code) (\(book.name))")
            }

            await MainActor.run {
                self.map = newMap
                self.indexedBookCount = bookCount
                self.isIndexing = false
            }

            logger.info("PresentationIndexer: Registered \(bookCount)/66 books (slides loaded on-demand)")

        } catch {
            await setError("Indexing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Lazy Lookup

    /// Look up a verse reference, loading the book's slides from Pro7 if needed.
    /// This is the primary lookup method - handles lazy loading transparently.
    func lookup(_ reference: BibleReference) async -> ProPresentationMap.SlideLocation? {
        let bookCode = reference.bookCode

        // Check if we need to load this book's slides
        if !map.isBookLoaded(bookCode) {
            guard let uuid = map.presentationUUID(for: bookCode) else {
                logger.error("PresentationIndexer.lookup: Book '\(bookCode)' not registered")
                return nil
            }

            // Load slides from Pro7
            await MainActor.run { self.currentlyLoadingBook = bookCode }
            defer { Task { @MainActor in self.currentlyLoadingBook = nil } }

            do {
                logger.info("PresentationIndexer: Loading slides for \(bookCode) (uuid: \(uuid.prefix(8))...)...")
                let slides = try await api.getPresentationSlides(presentationUUID: uuid)
                let labels = slides.map { $0.label }

                // Log first few labels for diagnostic purposes
                let sampleLabels = labels.prefix(5).map { "'\($0)'" }.joined(separator: ", ")
                logger.info("PresentationIndexer: \(bookCode) first labels: [\(sampleLabels)]")
                if let lastLabel = labels.last {
                    logger.info("PresentationIndexer: \(bookCode) last label: '\(lastLabel)'")
                }

                // Log empty labels that could indicate parsing issues
                let emptyCount = labels.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                if emptyCount > 0 {
                    logger.warning("PresentationIndexer: \(bookCode) has \(emptyCount) empty labels out of \(labels.count)")
                }

                await MainActor.run {
                    self.map.registerSlides(
                        bookCode: bookCode,
                        presentationUUID: uuid,
                        slideLabels: labels
                    )
                    self.indexedVerseCount = self.map.totalVerses
                }

                logger.info("PresentationIndexer: Loaded \(slides.count) slides for \(bookCode)")
            } catch {
                logger.error("PresentationIndexer: Failed to load slides for \(bookCode): \(error.localizedDescription)")
                logger.error("PresentationIndexer: Error type: \(type(of: error)), details: \(error)")
                return nil
            }
        }

        // Now look up the verse
        return map.lookup(reference)
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
        logger.error("PresentationIndexer: \(message)")
        await MainActor.run {
            self.errorMessage = message
            self.isIndexing = false
        }
    }
}
