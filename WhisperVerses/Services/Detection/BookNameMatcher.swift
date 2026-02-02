import Foundation

/// A book name occurrence found in text, with its position and matched book.
struct BookNameOccurrence {
    let book: BibleBook
    let range: Range<String.Index>
    let matchedName: String
}

/// Matches spoken or abbreviated book names to canonical Bible book names.
/// Supports exact alias lookup, ordinal prefix normalization, and Levenshtein fuzzy matching.
struct BookNameMatcher {
    private let bookIndex: BibleBookIndex
    /// All (lowercased name, book) pairs sorted by name length descending.
    /// Longer names are checked first to prevent partial matches
    /// (e.g., "1 Corinthians" before "1 Cor").
    private let sortedNames: [(String, BibleBook)]

    init(bookIndex: BibleBookIndex) {
        self.bookIndex = bookIndex
        self.sortedNames = bookIndex.books.flatMap { book in
            ([book.name.lowercased()] + book.aliases.map { $0.lowercased() })
                .map { ($0, book) }
        }
        .sorted { $0.0.count > $1.0.count }
    }

    // MARK: - Text Scanning

    /// Find all book name occurrences in text, returning positions and matched books.
    /// Longer names are matched first to prevent partial matches.
    func findAllOccurrences(in text: String) -> [BookNameOccurrence] {
        let lowerText = text.lowercased()
        var results: [BookNameOccurrence] = []
        var coveredRanges: [Range<String.Index>] = []

        for (name, book) in sortedNames {
            // Skip very short aliases (< 2 chars) to reduce noise
            guard name.count >= 2 else { continue }

            var searchStart = lowerText.startIndex
            while searchStart < lowerText.endIndex,
                  let range = lowerText.range(of: name, range: searchStart..<lowerText.endIndex) {
                defer { searchStart = range.upperBound }

                // Skip if overlapping with a longer match already found
                if coveredRanges.contains(where: { $0.overlaps(range) }) { continue }

                // Check word boundaries
                if !isWordBoundary(before: range.lowerBound, in: lowerText) { continue }
                if !isWordBoundary(after: range.upperBound, in: lowerText) { continue }

                // Use the range in the original text (same indices work since lowercasing preserves structure)
                results.append(BookNameOccurrence(book: book, range: range, matchedName: name))
                coveredRanges.append(range)
            }
        }

        return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - Single Name Matching

    /// Match a single book name string to a BibleBook.
    /// Tries exact lookup, prefix normalization, common misspellings, then fuzzy matching.
    func match(_ input: String) -> BibleBook? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 1. Direct lookup (handles exact names and all aliases)
        if let book = bookIndex.lookup(cleaned) { return book }

        // 2. Normalize ordinal prefixes: "First" → "1", "Second" → "2", "Third" → "3"
        let normalized = normalizePrefix(cleaned)
        if normalized != cleaned, let book = bookIndex.lookup(normalized) { return book }

        // 3. Fuzzy match using Levenshtein distance
        return fuzzyMatch(cleaned)
    }

    // MARK: - Private Helpers

    private func normalizePrefix(_ name: String) -> String {
        let prefixMap: [(String, String)] = [
            ("first ", "1 "), ("second ", "2 "), ("third ", "3 "),
            ("1st ", "1 "), ("2nd ", "2 "), ("3rd ", "3 "),
        ]
        let lower = name.lowercased()
        for (spoken, numeric) in prefixMap {
            if lower.hasPrefix(spoken) {
                return numeric + String(name.dropFirst(spoken.count))
            }
        }
        return name
    }

    private func fuzzyMatch(_ input: String) -> BibleBook? {
        let lower = input.lowercased()
        // Scale threshold: short names allow fewer edits
        let threshold = lower.count <= 5 ? 1 : (lower.count <= 10 ? 2 : 3)

        var bestMatch: BibleBook?
        var bestDistance = Int.max

        for book in bookIndex.books {
            let names = [book.name.lowercased()] + book.aliases.map { $0.lowercased() }
            for name in names {
                // Skip very short aliases for fuzzy matching to avoid noise
                guard name.count >= 3 else { continue }
                // Skip if length difference is too large
                guard abs(name.count - lower.count) <= threshold else { continue }

                let dist = levenshteinDistance(lower, name)
                if dist < bestDistance && dist <= threshold {
                    bestDistance = dist
                    bestMatch = book
                }
            }
        }

        return bestMatch
    }

    private func isWordBoundary(before index: String.Index, in text: String) -> Bool {
        if index == text.startIndex { return true }
        let prev = text[text.index(before: index)]
        return !prev.isLetter && !prev.isNumber
    }

    private func isWordBoundary(after index: String.Index, in text: String) -> Bool {
        if index == text.endIndex { return true }
        let next = text[index]
        return !next.isLetter && !next.isNumber
    }

    /// Compute Levenshtein edit distance between two strings.
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost  // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }
}
