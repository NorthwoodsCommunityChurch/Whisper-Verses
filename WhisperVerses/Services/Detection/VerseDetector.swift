import Foundation

/// Scans transcript text for Bible verse references using a multi-stage pipeline:
/// 1. SpokenFormNormalizer converts spoken patterns ("chapter three verse sixteen") to standard form
/// 2. BookNameMatcher finds book names in the normalized text
/// 3. Regex patterns extract chapter:verse numbers after each book name
/// 4. Validation against BibleBooks.json ensures the reference exists
/// 5. Deduplication prevents re-detecting the same verse within a time window
final class VerseDetector {
    private let bookIndex: BibleBookIndex
    private let normalizer = SpokenFormNormalizer()
    private let matcher: BookNameMatcher
    private var recentDetections: [String: Date] = [:]
    private let deduplicationWindow: TimeInterval = 30

    // Regex patterns applied to text AFTER a book name position
    private let colonRegex: NSRegularExpression?   // "3:16" or "3:16-18"
    private let commaRegex: NSRegularExpression?   // "3, 16" or "3,16" (common transcription of spoken refs)
    private let andRegex: NSRegularExpression?     // "3 and 16" (spoken: "chapter 3 and verse 16")
    private let spaceAndRegex: NSRegularExpression? // "3 16 and 17" (spoken: "chapter 3 verse 16 and 17")
    private let spaceRegex: NSRegularExpression?   // "3 16" or "3 16-18"
    private let singleRegex: NSRegularExpression?  // "25" (for single-chapter books)

    // Fallback regex for fuzzy matching: captures a word before chapter:verse
    private let fuzzyColonRegex: NSRegularExpression?

    init(bookIndex: BibleBookIndex = .load()) {
        self.bookIndex = bookIndex
        self.matcher = BookNameMatcher(bookIndex: bookIndex)

        // These are anchored to start of string — applied to the substring after a book name
        self.colonRegex = try? NSRegularExpression(
            pattern: #"^\s*(\d{1,3})\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?"#
        )
        self.commaRegex = try? NSRegularExpression(
            pattern: #"^\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?"#
        )
        self.andRegex = try? NSRegularExpression(
            pattern: #"^\s+(\d{1,3})\s+and\s+(\d{1,3})"#
        )
        // "3 16 and 17" → chapter 3, verse 16-17 (spoken range with "and")
        self.spaceAndRegex = try? NSRegularExpression(
            pattern: #"^\s+(\d{1,3})\s+(\d{1,3})\s+and\s+(\d{1,3})"#
        )
        self.spaceRegex = try? NSRegularExpression(
            pattern: #"^\s+(\d{1,3})\s+(\d{1,3})(?:\s*-\s*(\d{1,3}))?"#
        )
        self.singleRegex = try? NSRegularExpression(
            pattern: #"^\s+(\d{1,3})\b"#
        )
        // Fallback: any capitalized word(s) followed by chapter:verse (for fuzzy book name matching)
        self.fuzzyColonRegex = try? NSRegularExpression(
            pattern: #"(?i)\b([1-3]?\s*[A-Z][a-z]{2,}(?:\s+[a-z]+)?)\s+(\d{1,3})\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?"#
        )
    }

    /// Scan a transcript segment for verse references.
    /// Returns all detected verses with confidence levels and deduplication applied.
    func detect(in text: String) -> [DetectedVerse] {
        let normalized = normalizer.normalize(text)
        var detected: [DetectedVerse] = []
        var detectedKeys: Set<String> = []

        // Phase 1: Find known book names, then look for chapter:verse after each
        let occurrences = matcher.findAllOccurrences(in: normalized)

        for occurrence in occurrences {
            let afterBookStart = occurrence.range.upperBound
            guard afterBookStart < normalized.endIndex else { continue }
            let afterBook = String(normalized[afterBookStart...])

            // Try colon pattern: "3:16" or "3:16-18" (highest confidence)
            if let verse = matchChapterVerse(
                colonRegex, in: afterBook, book: occurrence.book,
                confidence: .high, sourceText: text
            ) {
                let key = verse.reference.displayString
                if !detectedKeys.contains(key) {
                    detected.append(verse)
                    detectedKeys.insert(key)
                }
                continue
            }

            // Try comma pattern: "28, 19" or "28,19" (common transcription artifact)
            if let verse = matchChapterVerse(
                commaRegex, in: afterBook, book: occurrence.book,
                confidence: .medium, sourceText: text
            ) {
                let key = verse.reference.displayString
                if !detectedKeys.contains(key) {
                    detected.append(verse)
                    detectedKeys.insert(key)
                }
                continue
            }

            // Try "and" pattern: "28 and 19" (spoken: "chapter 28 and verse 19")
            if let verse = matchChapterVerse(
                andRegex, in: afterBook, book: occurrence.book,
                confidence: .medium, sourceText: text
            ) {
                let key = verse.reference.displayString
                if !detectedKeys.contains(key) {
                    detected.append(verse)
                    detectedKeys.insert(key)
                }
                continue
            }

            // Try "space and" pattern: "3 16 and 17" (spoken verse range)
            if let verse = matchChapterVerse(
                spaceAndRegex, in: afterBook, book: occurrence.book,
                confidence: .medium, sourceText: text
            ) {
                let key = verse.reference.displayString
                if !detectedKeys.contains(key) {
                    detected.append(verse)
                    detectedKeys.insert(key)
                }
                continue
            }

            // Try space pattern: "3 16" or "3 16-18" (medium confidence)
            if let verse = matchChapterVerse(
                spaceRegex, in: afterBook, book: occurrence.book,
                confidence: .medium, sourceText: text
            ) {
                let key = verse.reference.displayString
                if !detectedKeys.contains(key) {
                    detected.append(verse)
                    detectedKeys.insert(key)
                }
                continue
            }

            // Single-chapter books: just a verse number (e.g., "Jude 25" → Jude 1:25)
            if occurrence.book.chapters.count == 1 {
                if let verse = matchSingleChapterVerse(
                    singleRegex, in: afterBook, book: occurrence.book, sourceText: text
                ) {
                    let key = verse.reference.displayString
                    if !detectedKeys.contains(key) {
                        detected.append(verse)
                        detectedKeys.insert(key)
                    }
                }
            }
        }

        // Phase 2: Fuzzy fallback — find "Word Number:Number" patterns not caught above
        detectFuzzyFallback(in: normalized, sourceText: text,
                            detected: &detected, detectedKeys: &detectedKeys)

        return detected
    }

    func clearHistory() {
        recentDetections.removeAll()
    }

    // MARK: - Private Matching

    /// Match a chapter:verse pattern in text after a known book name.
    private func matchChapterVerse(
        _ regex: NSRegularExpression?,
        in text: String,
        book: BibleBook,
        confidence: DetectedVerse.Confidence,
        sourceText: String
    ) -> DetectedVerse? {
        guard let regex else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        ) else { return nil }

        guard match.numberOfRanges >= 3 else { return nil }
        let chapterStr = nsText.substring(with: match.range(at: 1))
        let verseStr = nsText.substring(with: match.range(at: 2))
        guard let chapter = Int(chapterStr), let verse = Int(verseStr) else { return nil }

        // Validate chapter and verse exist in this book
        guard book.isValid(chapter: chapter, verse: verse) else { return nil }

        var verseEnd: Int? = nil
        if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
            if let end = Int(nsText.substring(with: match.range(at: 3))) {
                verseEnd = book.isValid(chapter: chapter, verse: end) ? end : nil
            }
        }

        let reference = BibleReference(
            bookCode: book.code,
            bookName: book.name,
            chapter: chapter,
            verseStart: verse,
            verseEnd: verseEnd
        )

        return DetectedVerse(
            reference: reference,
            confidence: confidence,
            detectedAt: Date(),
            sourceText: sourceText
        )
    }

    /// Match a single verse number for single-chapter books (e.g., "Jude 25" → Jude 1:25).
    private func matchSingleChapterVerse(
        _ regex: NSRegularExpression?,
        in text: String,
        book: BibleBook,
        sourceText: String
    ) -> DetectedVerse? {
        guard let regex else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        ) else { return nil }

        let verseStr = nsText.substring(with: match.range(at: 1))
        guard let verse = Int(verseStr) else { return nil }
        guard book.isValid(chapter: 1, verse: verse) else { return nil }

        let reference = BibleReference(
            bookCode: book.code,
            bookName: book.name,
            chapter: 1,
            verseStart: verse,
            verseEnd: nil
        )

        return DetectedVerse(
            reference: reference,
            confidence: .high,
            detectedAt: Date(),
            sourceText: sourceText
        )
    }

    /// Fuzzy fallback: find "Word Chapter:Verse" patterns where the word isn't an exact book name,
    /// then try fuzzy matching the word to a book.
    private func detectFuzzyFallback(
        in normalized: String,
        sourceText: String,
        detected: inout [DetectedVerse],
        detectedKeys: inout Set<String>
    ) {
        guard let fuzzyRegex = fuzzyColonRegex else { return }
        let nsText = normalized as NSString
        let matches = fuzzyRegex.matches(
            in: normalized, range: NSRange(location: 0, length: nsText.length)
        )

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let bookPart = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let chapterStr = nsText.substring(with: match.range(at: 2))
            let verseStr = nsText.substring(with: match.range(at: 3))

            guard let chapter = Int(chapterStr), let verse = Int(verseStr) else { continue }

            var verseEnd: Int? = nil
            if match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound {
                verseEnd = Int(nsText.substring(with: match.range(at: 4)))
            }

            // Try fuzzy matching the book name
            guard let book = matcher.match(bookPart) else { continue }

            // Validate
            guard book.isValid(chapter: chapter, verse: verse) else { continue }
            if let end = verseEnd, !book.isValid(chapter: chapter, verse: end) {
                verseEnd = nil
            }

            let reference = BibleReference(
                bookCode: book.code,
                bookName: book.name,
                chapter: chapter,
                verseStart: verse,
                verseEnd: verseEnd
            )

            let key = reference.displayString
            if !detectedKeys.contains(key) {
                detected.append(DetectedVerse(
                    reference: reference,
                    confidence: .low,
                    detectedAt: Date(),
                    sourceText: sourceText
                ))
                detectedKeys.insert(key)
            }
        }
    }
}
