import Foundation

/// Converts English number words to digit strings.
/// e.g., "sixteen" → "16", "twenty eight" → "28"
struct NumberWordConverter {
    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4,
        "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
        "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
        "eighteenth": 18, "nineteenth": 19,
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90
    ]

    /// Ordinal ones used as the second part of compound ordinals: "twenty-first" → 1
    private static let ordinalOnes: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4,
        "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9
    ]

    /// Convert a number word or phrase to a string digit. Returns nil if not a number word.
    /// All words in the input must be part of the number; unrecognized trailing words cause nil.
    static func convert(_ input: String) -> String? {
        let trimmed = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Already a number?
        if Int(trimmed) != nil {
            return trimmed
        }

        // Single word: ones, tens, ordinals
        if let value = ones[trimmed] { return String(value) }
        if let value = tens[trimmed] { return String(value) }
        if let value = ordinals[trimmed] { return String(value) }

        // Hyphenated: "twenty-eight" or "twenty-first"
        let hyphenParts = trimmed.split(separator: "-").map(String.init)
        if hyphenParts.count == 2, let t = tens[hyphenParts[0]] {
            if let o = ones[hyphenParts[1]] { return String(t + o) }
            if let o = ordinalOnes[hyphenParts[1]] { return String(t + o) }
        }

        // Multi-word
        let words = trimmed.split(separator: " ").map(String.init)

        // Two words: "twenty eight" or "twenty first"
        if words.count == 2, let t = tens[words[0]] {
            if let o = ones[words[1]] { return String(t + o) }
            if let o = ordinalOnes[words[1]] { return String(t + o) }
        }

        // "hundred" patterns — all words must be consumed
        // Supports both "one hundred" and "a hundred"
        if let hundredIdx = words.firstIndex(of: "hundred"), hundredIdx > 0 {
            guard hundredIdx == 1 else { return nil }
            let multiplier: Int?
            if words[0] == "a" {
                multiplier = 1
            } else {
                multiplier = ones[words[0]]
            }
            guard let h = multiplier else { return nil }
            var value = h * 100

            let remaining = Array(words.dropFirst(hundredIdx + 1).filter { $0 != "and" })
            if remaining.isEmpty {
                return String(value)
            } else if remaining.count == 1 {
                if let t = tens[remaining[0]] { value += t }
                else if let o = ones[remaining[0]] { value += o }
                else if let o = ordinals[remaining[0]] { value += o }
                else {
                    // Hyphenated compound in remainder: "twenty-first"
                    let parts = remaining[0].split(separator: "-").map(String.init)
                    if parts.count == 2, let t = tens[parts[0]] {
                        if let o = ones[parts[1]] { value += t + o }
                        else if let o = ordinalOnes[parts[1]] { value += t + o }
                        else { return nil }
                    } else { return nil }
                }
                return String(value)
            } else if remaining.count == 2 {
                if let t = tens[remaining[0]] {
                    if let o = ones[remaining[1]] { value += t + o }
                    else if let o = ordinalOnes[remaining[1]] { value += t + o }
                    else { return nil }
                } else { return nil }
                return String(value)
            }
            return nil
        }

        return nil
    }

    /// Replace all number word sequences in text with digit strings.
    /// Processes greedily, trying the longest matching sequence first.
    /// e.g., "John three sixteen" → "John 3 16"
    /// e.g., "one hundred and fifty three" → "153"
    static func replaceNumberWordsInText(_ text: String) -> String {
        let tokens = text.components(separatedBy: " ")
        var output: [String] = []
        var i = 0

        while i < tokens.count {
            // Skip empty tokens (from multiple spaces)
            guard !tokens[i].isEmpty else {
                output.append(tokens[i])
                i += 1
                continue
            }

            var bestLen = 0
            var bestVal = ""

            // Try longest match first (up to 6 words for "one hundred and twenty eight")
            let maxLookahead = min(6, tokens.count - i)
            for len in stride(from: maxLookahead, through: 1, by: -1) {
                let phrase = tokens[i..<(i + len)].joined(separator: " ")
                // Strip trailing punctuation for matching
                let cleaned = phrase.trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                guard !cleaned.isEmpty else { continue }

                if let val = convert(cleaned) {
                    bestLen = len
                    bestVal = val
                    break
                }
            }

            if bestLen > 0 {
                // Preserve any trailing punctuation from the last token
                let lastToken = tokens[i + bestLen - 1]
                let trailing = lastToken.reversed().prefix(while: { $0.isPunctuation })
                output.append(bestVal + String(trailing.reversed()))
                i += bestLen
            } else {
                output.append(tokens[i])
                i += 1
            }
        }

        return output.joined(separator: " ")
    }
}
