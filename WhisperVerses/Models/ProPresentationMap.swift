import Foundation
import os.log

private let logger = Logger(subsystem: "com.whisperverses", category: "ProPresentationMap")

/// Maps Bible verse references to ProPresenter slide locations.
/// Uses actual slide labels from Pro7 presentations for accurate lookups,
/// independent of Bible translation verse numbering differences.
///
/// Supports lazy loading: books are registered with just their UUID first,
/// then slides are fetched on-demand when a verse from that book is needed.
struct ProPresentationMap {

    struct SlideLocation {
        let presentationUUID: String
        let slideIndex: Int
    }

    /// Book code → presentation UUID (populated during initial index)
    private var bookPresentations: [String: String] = [:]

    /// Maps "BookName Chapter:Verse" → SlideLocation
    /// e.g., "Matthew 28:19" → SlideLocation(uuid, 1066)
    /// Populated lazily per book when first accessed.
    private var verseLookup: [String: SlideLocation] = [:]

    /// Tracks which book codes have had their slides loaded
    private var loadedBooks: Set<String> = []

    /// Register a book with its presentation UUID (fast, no slide fetching).
    /// Call this during initial indexing for all 66 books.
    mutating func registerBook(bookCode: String, presentationUUID: String) {
        bookPresentations[bookCode] = presentationUUID
        logger.debug("ProPresentationMap: Registered book \(bookCode) → \(presentationUUID.prefix(8))...")
    }

    /// Register all slides from a presentation, parsing verse labels.
    /// Labels are expected to be in format "BookName Chapter:Verse" (e.g., "Matthew 28:19").
    /// Called lazily when a book's verses are first accessed.
    mutating func registerSlides(bookCode: String, presentationUUID: String, slideLabels: [String]) {
        loadedBooks.insert(bookCode)

        var addedCount = 0
        for (index, label) in slideLabels.enumerated() {
            // Store the label exactly as Pro7 has it
            let normalizedLabel = label.trimmingCharacters(in: .whitespaces)
            if !normalizedLabel.isEmpty {
                verseLookup[normalizedLabel] = SlideLocation(
                    presentationUUID: presentationUUID,
                    slideIndex: index
                )
                addedCount += 1
            }
        }

        logger.info("ProPresentationMap: Loaded \(addedCount) slides for \(bookCode)")
    }

    /// Look up the Pro7 slide location for a verse reference.
    /// Constructs the label string and searches for it in the map.
    /// Returns nil if the book's slides haven't been loaded yet - caller should load them first.
    func lookup(_ reference: BibleReference) -> SlideLocation? {
        // Construct the label in the format Pro7 uses: "BookName Chapter:Verse"
        let label = "\(reference.bookName) \(reference.chapter):\(reference.verseStart)"

        if let location = verseLookup[label] {
            return location
        }

        // Log detailed error for debugging
        let bookLoaded = loadedBooks.contains(reference.bookCode)
        logger.error("ProPresentationMap.lookup: FAILED - No slide for '\(label)'")
        logger.error("  - bookCode: \(reference.bookCode), hasBook: \(bookPresentations[reference.bookCode] != nil), loaded: \(bookLoaded)")
        logger.error("  - Total verses indexed: \(verseLookup.count)")

        // Show similar labels in the map to help diagnose format mismatches
        let bookPrefix = reference.bookName
        let similarKeys = verseLookup.keys.filter { $0.hasPrefix(bookPrefix) }.sorted().prefix(5)
        if !similarKeys.isEmpty {
            logger.error("  - Similar labels in map: \(similarKeys.joined(separator: ", "))")
        } else {
            logger.error("  - No labels found starting with '\(bookPrefix)' — book slides may not have loaded")
        }

        return nil
    }

    /// Check if a book has been registered (has a presentation UUID).
    func hasBook(_ bookCode: String) -> Bool {
        bookPresentations[bookCode] != nil
    }

    /// Check if a book's slides have been loaded.
    func isBookLoaded(_ bookCode: String) -> Bool {
        loadedBooks.contains(bookCode)
    }

    /// Get the presentation UUID for a book (for lazy loading).
    func presentationUUID(for bookCode: String) -> String? {
        bookPresentations[bookCode]
    }

    var isEmpty: Bool { bookPresentations.isEmpty }
    var count: Int { bookPresentations.count }
    var loadedCount: Int { loadedBooks.count }
    var totalVerses: Int { verseLookup.count }
}
