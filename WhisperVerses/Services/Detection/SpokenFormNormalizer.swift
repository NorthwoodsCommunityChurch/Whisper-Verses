import Foundation

/// Converts spoken Bible reference forms to standard format.
/// e.g., "John chapter three verse sixteen" → "John 3:16"
/// e.g., "First Corinthians thirteen four through seven" → "1 Corinthians 13 4-7"
struct SpokenFormNormalizer {

    /// Normalize spoken Bible reference patterns in text.
    /// Processes patterns in order of specificity, then converts number words to digits.
    func normalize(_ text: String) -> String {
        var result = text

        // 1. "chapter X verse(s) Y through/to Z" → "X:Y-Z"
        result = replacePattern(
            #"(?i)\bchapter\s+(\w+(?:[\s-]\w+)?)\s*,?\s*verse[s]?\s+(\w+(?:[\s-]\w+)?)\s+(?:through|to|thru)\s+(\w+(?:[\s-]\w+)?)"#,
            in: result
        ) { _, groups in
            guard groups.count >= 3 else { return nil }
            let ch = NumberWordConverter.convert(groups[0]) ?? groups[0]
            let vs = NumberWordConverter.convert(groups[1]) ?? groups[1]
            let ve = NumberWordConverter.convert(groups[2]) ?? groups[2]
            return "\(ch):\(vs)-\(ve)"
        }

        // 2. "chapter X verse(s) Y" → "X:Y"
        result = replacePattern(
            #"(?i)\bchapter\s+(\w+(?:[\s-]\w+)?)\s*,?\s*verse[s]?\s+(\w+(?:[\s-]\w+)?)"#,
            in: result
        ) { _, groups in
            guard groups.count >= 2 else { return nil }
            let ch = NumberWordConverter.convert(groups[0]) ?? groups[0]
            let vs = NumberWordConverter.convert(groups[1]) ?? groups[1]
            return "\(ch):\(vs)"
        }

        // 3. "verses X through/to Y" → "X-Y" (range without chapter keyword)
        result = replacePattern(
            #"(?i)\bverse[s]?\s+(\w+(?:[\s-]\w+)?)\s+(?:through|to|thru)\s+(\w+(?:[\s-]\w+)?)"#,
            in: result
        ) { _, groups in
            guard groups.count >= 2 else { return nil }
            let vs = NumberWordConverter.convert(groups[0]) ?? groups[0]
            let ve = NumberWordConverter.convert(groups[1]) ?? groups[1]
            return "\(vs)-\(ve)"
        }

        // 3.5. "verses X and Y" → "X-Y" (range with "and" connector)
        // Handles: "verses 20 and 21", "verse 28 and 29"
        result = replacePattern(
            #"(?i)\bverse[s]?\s+(\w+(?:[\s-]\w+)?)\s+and\s+(\w+(?:[\s-]\w+)?)"#,
            in: result
        ) { _, groups in
            guard groups.count >= 2 else { return nil }
            let vs = NumberWordConverter.convert(groups[0]) ?? groups[0]
            let ve = NumberWordConverter.convert(groups[1]) ?? groups[1]
            return "\(vs)-\(ve)"
        }

        // 4. "verse X" → just the number
        result = replacePattern(
            #"(?i)\bverse[s]?\s+(\w+(?:[\s-]\w+)?)\b"#,
            in: result
        ) { fullMatch, groups in
            guard groups.count >= 1 else { return nil }
            return NumberWordConverter.convert(groups[0]) ?? nil
        }

        // 5. Strip "the book of" prefix
        result = replacePattern(
            #"(?i)\bthe\s+book\s+of\s+"#,
            in: result
        ) { _, _ in "" }

        // 6. Replace number words with digits throughout
        result = NumberWordConverter.replaceNumberWordsInText(result)

        // 7. Replace "through/to/thru" between digits with "-"
        result = replacePattern(
            #"(\d+)\s+(?:through|to|thru)\s+(\d+)"#,
            in: result
        ) { _, groups in
            guard groups.count >= 2 else { return nil }
            return "\(groups[0])-\(groups[1])"
        }

        // 8. Handle "chapter in verse-range" pattern: "1 in 20-21" → "1:20-21"
        // This occurs when "verses X to Y" is normalized to "X-Y" but preceded by chapter
        result = replacePattern(
            #"(\d{1,3})\s+in\s+(\d{1,3})(?:-(\d{1,3}))?"#,
            in: result
        ) { _, groups in
            guard groups.count >= 2 else { return nil }
            let chapter = groups[0]
            let verseStart = groups[1]
            if groups.count >= 3 {
                let verseEnd = groups[2]
                return "\(chapter):\(verseStart)-\(verseEnd)"
            }
            return "\(chapter):\(verseStart)"
        }

        return result
    }

    // MARK: - Private

    /// Apply a regex replacement using a transform closure.
    /// The closure receives the full match string and an array of capture group strings.
    /// Return nil from the closure to keep the original text unchanged.
    private func replacePattern(
        _ pattern: String,
        in text: String,
        transform: (String, [String]) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = text
        // Process matches in reverse to preserve earlier indices
        for match in matches.reversed() {
            let fullMatch = nsText.substring(with: match.range)
            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                if match.range(at: i).location != NSNotFound {
                    groups.append(nsText.substring(with: match.range(at: i)))
                }
            }
            if let replacement = transform(fullMatch, groups) {
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        return result
    }
}
