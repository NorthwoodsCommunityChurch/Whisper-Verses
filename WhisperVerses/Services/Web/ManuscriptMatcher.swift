import Foundation

struct ManuscriptChunk {
    let text: String
    let normalizedText: String
    let wordSet: Set<String>
    let bigramSet: [String]
    let trigramSet: [String]
}

enum ManuscriptMatcher {
    /// Target size for each chunk (~5 sentences for balance)
    private static let targetChunkSize = 5

    /// Number of recent words from transcript to use for matching
    private static let transcriptWordWindow = 25

    /// Parse manuscript text into chunks
    static func parseIntoChunks(_ text: String) -> [ManuscriptChunk] {
        let sentences = splitIntoSentences(text)

        guard !sentences.isEmpty else { return [] }

        var chunks: [ManuscriptChunk] = []
        var currentSentences: [String] = []

        for sentence in sentences {
            currentSentences.append(sentence)

            if currentSentences.count >= targetChunkSize {
                let chunkText = currentSentences.joined(separator: " ")
                let words = extractWords(chunkText)
                chunks.append(ManuscriptChunk(
                    text: chunkText,
                    normalizedText: words.joined(separator: " "),
                    wordSet: Set(words),
                    bigramSet: [],
                    trigramSet: []
                ))
                currentSentences.removeAll()
            }
        }

        // Add remaining sentences as final chunk
        if !currentSentences.isEmpty {
            let chunkText = currentSentences.joined(separator: " ")
            let words = extractWords(chunkText)
            chunks.append(ManuscriptChunk(
                text: chunkText,
                normalizedText: words.joined(separator: " "),
                wordSet: Set(words),
                bigramSet: [],
                trigramSet: []
            ))
        }

        return chunks
    }

    /// Split text into sentences
    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var currentSentence = ""

        let terminators: Set<Character> = [".", "!", "?"]

        for char in text {
            currentSentence.append(char)

            if terminators.contains(char) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                currentSentence = ""
            }
        }

        // Add any remaining text
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }

        return sentences
    }

    /// Calculate match score using weighted word overlap
    /// Recent words in transcript are weighted more heavily
    static func matchScore(transcript: String, chunk: ManuscriptChunk) -> Double {
        let transcriptWords = extractWords(transcript)

        guard !transcriptWords.isEmpty && !chunk.wordSet.isEmpty else { return 0.0 }

        // Use last N words of transcript (most recent speech)
        let recentWords: [String]
        if transcriptWords.count > transcriptWordWindow {
            recentWords = Array(transcriptWords.suffix(transcriptWordWindow))
        } else {
            recentWords = transcriptWords
        }

        // Simple weighted word overlap
        // More recent words get higher weight
        var matchCount = 0
        var weightedMatches = 0.0
        var totalWeight = 0.0

        for (index, word) in recentWords.enumerated() {
            // Linear weight: oldest word = 0.5, newest = 1.0
            let weight = 0.5 + 0.5 * (Double(index) / Double(max(1, recentWords.count - 1)))
            totalWeight += weight

            if chunk.wordSet.contains(word) {
                weightedMatches += weight
                matchCount += 1
            }
        }

        guard totalWeight > 0 else { return 0.0 }

        return weightedMatches / totalWeight
    }

    /// Legacy match score for backwards compatibility
    static func matchScore(transcript: String, chunk: String) -> Double {
        let transcriptWords = extractWords(transcript)
        let chunkWords = Set(extractWords(chunk))

        guard !transcriptWords.isEmpty && !chunkWords.isEmpty else { return 0.0 }

        let recentWords: [String]
        if transcriptWords.count > transcriptWordWindow {
            recentWords = Array(transcriptWords.suffix(transcriptWordWindow))
        } else {
            recentWords = transcriptWords
        }

        var weightedMatches = 0.0
        var totalWeight = 0.0

        for (index, word) in recentWords.enumerated() {
            let weight = 0.5 + 0.5 * (Double(index) / Double(max(1, recentWords.count - 1)))
            totalWeight += weight

            if chunkWords.contains(word) {
                weightedMatches += weight
            }
        }

        guard totalWeight > 0 else { return 0.0 }

        return weightedMatches / totalWeight
    }

    /// Extract normalized words from text
    private static func extractWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 } // Ignore 1-2 letter words (the, is, a, etc.)
    }

    /// Normalize text for comparison (kept for compatibility)
    static func normalize(_ text: String) -> String {
        extractWords(text).joined(separator: " ")
    }
}
