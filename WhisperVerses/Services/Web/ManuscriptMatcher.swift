import Foundation

enum ManuscriptMatcher {
    /// Target size for each chunk (~5 sentences)
    private static let targetChunkSize = 5

    /// Number of recent characters from transcript to use for matching
    private static let transcriptWindowSize = 150

    /// Parse manuscript text into chunks of approximately 5 sentences each
    static func parseIntoChunks(_ text: String) -> [ManuscriptChunk] {
        let sentences = splitIntoSentences(text)

        guard !sentences.isEmpty else { return [] }

        var chunks: [ManuscriptChunk] = []
        var currentSentences: [String] = []

        for sentence in sentences {
            currentSentences.append(sentence)

            if currentSentences.count >= targetChunkSize {
                let chunkText = currentSentences.joined(separator: " ")
                chunks.append(ManuscriptChunk(
                    text: chunkText,
                    normalizedText: normalize(chunkText)
                ))
                currentSentences.removeAll()
            }
        }

        // Add remaining sentences as final chunk
        if !currentSentences.isEmpty {
            let chunkText = currentSentences.joined(separator: " ")
            chunks.append(ManuscriptChunk(
                text: chunkText,
                normalizedText: normalize(chunkText)
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

    /// Calculate match score between transcript and a chunk
    static func matchScore(transcript: String, chunk: String) -> Double {
        let normalizedTranscript = normalize(transcript)

        // Use last N characters of transcript for matching
        let window: String
        if normalizedTranscript.count > transcriptWindowSize {
            let startIndex = normalizedTranscript.index(normalizedTranscript.endIndex, offsetBy: -transcriptWindowSize)
            window = String(normalizedTranscript[startIndex...])
        } else {
            window = normalizedTranscript
        }

        guard !window.isEmpty && !chunk.isEmpty else { return 0.0 }

        // Calculate LCS-based similarity
        let lcsLength = longestCommonSubsequence(Array(window), Array(chunk))
        let maxLength = max(window.count, chunk.count)

        return Double(lcsLength) / Double(maxLength)
    }

    /// Normalize text for comparison
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Calculate length of longest common subsequence
    private static func longestCommonSubsequence(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty && !b.isEmpty else { return 0 }

        let m = a.count
        let n = b.count

        // Use optimized space - only need two rows
        var prev = [Int](repeating: 0, count: n + 1)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j - 1])
                }
            }
            swap(&prev, &curr)
            curr = [Int](repeating: 0, count: n + 1)
        }

        return prev[n]
    }
}
