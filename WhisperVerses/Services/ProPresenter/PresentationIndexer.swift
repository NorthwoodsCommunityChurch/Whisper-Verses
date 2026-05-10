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

    /// In-flight slide-load tasks keyed by bookCode. Lets concurrent lookups for
    /// the same book share a single Pro7 request instead of each firing their
    /// own. Without this, two simultaneous detections from one book (common
    /// during a sermon) issue two parallel 480KB+ loads and both can time out
    /// because Pro7's REST server doesn't handle that well. Mutated only on the
    /// main actor.
    @MainActor private var inFlightLoads: [String: Task<Bool, Never>] = [:]

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

            // Pay the cold-load tax now, in the background, before the sermon
            // starts. Otherwise the first verse from each book during a live
            // sermon blocks on a Pro7 request that can take 1–30s under load.
            // Run sequentially with a small inter-book delay so we don't
            // hammer Pro7's REST server (which is the same machine running
            // the live presentation).
            Task.detached(priority: .background) { [weak self] in
                await self?.warmupAllBooks()
            }

        } catch {
            await setError("Indexing failed: \(error.localizedDescription)")
        }
    }

    /// After initial indexing, proactively load every book's slide labels in
    /// the background so subsequent live captures don't pay the cold-load tax.
    /// Sequential with a short inter-book delay — Pro7's REST server doesn't
    /// like parallel large-presentation reads.
    private func warmupAllBooks() async {
        let bookCodes = await MainActor.run { self.bookIndex.books.map(\.code) }
        var warmedCount = 0
        let startTime = Date()
        ThreadSafeAudioProcessor.appendToDebugLog("[Pro7] Background warmup starting for \(bookCodes.count) books\n")

        for bookCode in bookCodes {
            // Skip books not registered with Pro7 (presentation missing for this translation).
            let registered = await MainActor.run { self.map.presentationUUID(for: bookCode) != nil }
            guard registered else { continue }

            // Skip books already loaded (e.g., a live capture beat warmup to it).
            let alreadyLoaded = await MainActor.run { self.map.isBookLoaded(bookCode) }
            if alreadyLoaded {
                warmedCount += 1
                continue
            }

            // Use the same coalescing path as live lookups so a real capture
            // happening at this exact moment shares the load instead of racing.
            if await self.ensureBookLoaded(bookCode: bookCode) {
                warmedCount += 1
            }

            // 200ms inter-book throttle so warmup doesn't starve the operator's
            // first live captures of Pro7 bandwidth.
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let elapsed = Int(Date().timeIntervalSince(startTime))
        let totalVerses = await MainActor.run { self.map.totalVerses }
        let msg = "[Pro7] Background warmup complete: \(warmedCount)/\(bookCodes.count) books, \(totalVerses) verses, \(elapsed)s"
        logger.info("\(msg)")
        ThreadSafeAudioProcessor.appendToDebugLog(msg + "\n")
    }

    // MARK: - Lazy Lookup

    /// Look up a verse reference, loading the book's slides from Pro7 if needed.
    /// This is the primary lookup method - handles lazy loading transparently.
    func lookup(_ reference: BibleReference) async -> ProPresentationMap.SlideLocation? {
        let bookCode = reference.bookCode

        if !map.isBookLoaded(bookCode) {
            let succeeded = await ensureBookLoaded(bookCode: bookCode)
            guard succeeded else { return nil }
        }

        return map.lookup(reference)
    }

    /// Ensure a book's slides are loaded, coalescing concurrent requests for
    /// the same book into one Pro7 call. Used by `lookup(_:)` and by the
    /// background warmup. Returns `true` if the book is loaded after this call.
    ///
    /// Without this coalescing, two simultaneous detections from one book
    /// (e.g. back-to-back Psalms references) would issue two parallel 480KB+
    /// loads and Pro7's REST server can't handle that — both can fail.
    ///
    /// Cleanup of `inFlightLoads[bookCode]` lives inside the task body so
    /// the entry is removed even if every awaiting caller is cancelled before
    /// the load completes — otherwise the slot would leak permanently.
    @discardableResult
    private func ensureBookLoaded(bookCode: String) async -> Bool {
        if map.isBookLoaded(bookCode) { return true }

        guard map.presentationUUID(for: bookCode) != nil else {
            logger.error("PresentationIndexer: Book '\(bookCode)' not registered")
            return false
        }

        let loadTask: Task<Bool, Never> = await MainActor.run {
            if let existing = self.inFlightLoads[bookCode] {
                return existing
            }
            let task = Task<Bool, Never> { [weak self] in
                guard let self else { return false }
                let result = await self.performBookLoad(bookCode: bookCode)
                await MainActor.run { self.inFlightLoads.removeValue(forKey: bookCode) }
                return result
            }
            self.inFlightLoads[bookCode] = task
            return task
        }

        return await loadTask.value
    }

    /// Perform the actual slide-load network call with retries.
    /// Returns true on success (slides registered), false on permanent failure.
    /// Called once per book at a time; concurrent callers share the same Task via `inFlightLoads`.
    private func performBookLoad(bookCode: String) async -> Bool {
        guard let uuid = await MainActor.run(body: { map.presentationUUID(for: bookCode) }) else {
            return false
        }

        await MainActor.run { self.currentlyLoadingBook = bookCode }
        defer { Task { @MainActor [weak self] in self?.currentlyLoadingBook = nil } }

        // Pro7's /v1/presentation/{uuid} is unreliable on cold load — first
        // attempt often returns HTTP 500, second can time out, third usually
        // succeeds. Bumped from 3 to 5 attempts and switched to exponential
        // backoff so larger books (Psalms, Genesis, Isaiah) survive Pro7's
        // recovery window. With the 30s URL request timeout this gives ~2.5
        // minutes of headroom per book before declaring permanent failure.
        var slides: [ProPresenterAPI.Slide]? = nil
        var lastError: Error? = nil
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            do {
                let msg = "[Pro7] Loading slides for \(bookCode) uuid=\(uuid.prefix(8))... (attempt \(attempt)/\(maxAttempts))"
                logger.info("\(msg)")
                ThreadSafeAudioProcessor.appendToDebugLog(msg + "\n")
                slides = try await api.getPresentationSlides(presentationUUID: uuid)
                ThreadSafeAudioProcessor.appendToDebugLog("[Pro7] Loaded \(slides?.count ?? 0) slides for \(bookCode)\n")
                break
            } catch {
                lastError = error
                let errorDesc = Self.describeError(error)
                let msg = "[Pro7] Attempt \(attempt) FAILED for \(bookCode): \(errorDesc)"
                logger.warning("\(msg)")
                ThreadSafeAudioProcessor.appendToDebugLog(msg + "\n")
                if attempt < maxAttempts {
                    // 500ms, 1s, 2s, 4s — total ~7.5s of backoff across 4 gaps
                    let backoffMs = UInt64(500 * (1 << (attempt - 1)))
                    try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                }
            }
        }

        guard let loadedSlides = slides else {
            let errorDesc = Self.describeError(lastError)
            let msg = "[Pro7] All \(maxAttempts) attempts FAILED for \(bookCode): \(errorDesc)"
            logger.error("\(msg)")
            ThreadSafeAudioProcessor.appendToDebugLog(msg + "\n")
            return false
        }

        let labels = loadedSlides.map { $0.label }

        let sampleLabels = labels.prefix(5).map { "'\($0)'" }.joined(separator: ", ")
        logger.info("PresentationIndexer: \(bookCode) first labels: [\(sampleLabels)]")
        if let lastLabel = labels.last {
            logger.info("PresentationIndexer: \(bookCode) last label: '\(lastLabel)'")
        }

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

        logger.info("PresentationIndexer: Loaded \(loadedSlides.count) slides for \(bookCode)")
        return true
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

    /// Produce a detailed error description including the error type, domain, and code
    /// so we can diagnose transient failures from the debug log on remote machines.
    private static func describeError(_ error: Error?) -> String {
        guard let error else { return "unknown (nil)" }
        let nsError = error as NSError
        var parts: [String] = []
        parts.append("type=\(type(of: error))")
        parts.append("domain=\(nsError.domain)")
        parts.append("code=\(nsError.code)")
        parts.append("desc=\(error.localizedDescription)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            let nsUnderlying = underlying as NSError
            parts.append("underlying=\(nsUnderlying.domain)/\(nsUnderlying.code): \(underlying.localizedDescription)")
        }
        return parts.joined(separator: ", ")
    }

    private func setError(_ message: String) async {
        logger.error("PresentationIndexer: \(message)")
        await MainActor.run {
            self.errorMessage = message
            self.isIndexing = false
        }
    }
}
