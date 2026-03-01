import Foundation
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "ForcedAlignment")

/// Manuscript following using sequence alignment
///
/// Mental model: Fitting puzzle pieces together
/// - Each transcript word is a puzzle piece
/// - We try to place it in the manuscript sequence
/// - Matched words form a "chain" showing our position
/// - The chain grows as more words match
final class ForcedAlignmentMatcher {

    // MARK: - Manuscript Data

    struct ManuscriptWord {
        let word: String
        let position: Int      // Word index in full manuscript
        let chunkIndex: Int    // Which chunk this word belongs to
    }

    private var manuscriptWords: [ManuscriptWord] = []
    private var wordToPositions: [String: [Int]] = [:]  // word → positions where it appears
    private var wordIDF: [String: Double] = [:]
    private var totalChunks = 0

    // MARK: - Alignment State

    /// Current estimated position (word index in manuscript)
    private var currentPosition: Int = 0

    /// Recent match positions - the "chain" of fitted pieces
    private var matchChain: [(transcriptIndex: Int, manuscriptPosition: Int, idf: Double, isConsecutive: Bool)] = []
    private let maxChainLength = 50

    /// All confirmed matched positions (cumulative, never removed until reset)
    /// Only positions that are part of consecutive runs get added here
    private var confirmedMatchedPositions: Set<Int> = []

    /// Track transcript words processed
    private var lastProcessedWordCount = 0
    private var transcriptWords: [String] = []

    /// Hysteresis: track how many updates we've been at a different chunk
    private var pendingChunkIndex: Int = 0
    private var pendingChunkCount: Int = 0
    private let chunkChangeThreshold = 8  // Need 8 consecutive updates at new chunk

    /// Track when we last added a consecutive match (for off-script detection)
    private var lastConsecutiveMatchTranscriptIndex: Int = 0

    // MARK: - Public

    private(set) var currentChunkIndex: Int = 0
    private(set) var matchConfidence: Double = 0.0
    private(set) var isOffScript: Bool = false

    // MARK: - Constants

    /// How far ahead of current position to search for matches
    private let forwardSearchWindow = 200  // words, not chunks

    /// How far behind to search (rarely needed)
    private let backwardSearchWindow = 30

    /// Minimum IDF to consider a word "useful" for matching
    /// Higher = only rare words count. 2.0 filters out common words that appear in many chunks.
    private let minUsefulIDF = 2.0

    /// How many recent chain links to use for position estimate
    private let chainWindowForPosition = 15

    // MARK: - Build Index

    func buildIndex(from chunks: [ManuscriptChunk]) {
        manuscriptWords.removeAll()
        wordToPositions.removeAll()
        wordIDF.removeAll()
        totalChunks = chunks.count

        // Build word list with positions
        var position = 0
        var wordChunkCount: [String: Set<Int>] = [:]  // word → which chunks contain it

        for (chunkIndex, chunk) in chunks.enumerated() {
            let words = normalizeText(chunk.text)

            for word in words {
                manuscriptWords.append(ManuscriptWord(
                    word: word,
                    position: position,
                    chunkIndex: chunkIndex
                ))

                wordToPositions[word, default: []].append(position)
                wordChunkCount[word, default: []].insert(chunkIndex)
                position += 1
            }
        }

        // Calculate IDF based on chunk distribution
        let totalChunksDouble = Double(totalChunks)
        for (word, chunkSet) in wordChunkCount {
            let idf = log((totalChunksDouble + 1) / (Double(chunkSet.count) + 1)) + 1
            wordIDF[word] = idf
        }

        // Log stats
        let sortedByIDF = wordIDF.sorted { $0.value > $1.value }
        let topWords = sortedByIDF.prefix(8).map { "\($0.key):\(String(format: "%.1f", $0.value))" }
        let bottomWords = sortedByIDF.suffix(5).map { "\($0.key):\(String(format: "%.1f", $0.value))" }

        logger.info("Index: \(self.manuscriptWords.count) words, \(chunks.count) chunks")
        logger.info("High IDF: \(topWords.joined(separator: ", "))")
        logger.info("Low IDF: \(bottomWords.joined(separator: ", "))")

        resetTracking()
    }

    // MARK: - Process Words

    func processWord(_ word: String) -> Int {
        return processWords([word])
    }

    func processWords(_ words: [String]) -> Int {
        guard !manuscriptWords.isEmpty else { return 0 }

        // Handle reset
        if words.count < lastProcessedWordCount {
            logger.info("Transcript reset")
            lastProcessedWordCount = 0
            transcriptWords.removeAll()
            matchChain.removeAll()
        }

        // Get new words
        let newWords = words.count > lastProcessedWordCount
            ? Array(words.dropFirst(lastProcessedWordCount))
            : []

        guard !newWords.isEmpty else { return currentChunkIndex }

        // CATCHUP: Trigger full-manuscript scan in two scenarios:
        // 1. First batch of words is long (>20 words) - starting mid-sermon
        // 2. Still near beginning with low confidence AND getting lots of new words - sermon just started
        let shouldCatchup = (lastProcessedWordCount == 0 && words.count > 20) ||
                           (currentChunkIndex < 3 && matchConfidence < 0.3 && newWords.count >= 15 && words.count >= 20)

        if shouldCatchup {
            performCatchupScan(words: words)
        }

        lastProcessedWordCount = words.count

        // Process each new word - try to fit it into the puzzle
        for word in newWords {
            let normalized = normalizeWord(word)
            guard !normalized.isEmpty else { continue }

            transcriptWords.append(normalized)
            tryToFitWord(normalized, transcriptIndex: transcriptWords.count - 1)
        }

        // Update position estimate from match chain
        updatePositionFromChain()

        return currentChunkIndex
    }

    /// Catchup scan: when starting late, find where in the manuscript we likely are
    private func performCatchupScan(words: [String]) {
        logger.info("CATCHUP: Scanning manuscript with \(words.count) initial words")

        let normalized = words.map { normalizeWord($0) }.filter { !$0.isEmpty }
        guard normalized.count >= 10 else { return }

        // Use the first 30 words for catchup (enough to find position)
        let searchWindow = Array(normalized.prefix(30))

        // Score each POSITION in manuscript by sequence match quality
        // Look for consecutive runs of matching words (like the regular matcher does)
        var bestScore = 0.0
        var bestPosition = 0

        // Scan entire manuscript with sliding window
        for startPos in 0..<manuscriptWords.count {
            // Extract a window of manuscript words to compare
            let windowSize = min(50, manuscriptWords.count - startPos)
            let manuscriptWindow = Array(manuscriptWords[startPos..<(startPos + windowSize)])

            var score = 0.0
            var consecutiveMatches = 0

            // Try to align search words with this manuscript position
            for (transcriptIdx, transcriptWord) in searchWindow.enumerated() {
                // Look for this word in the manuscript window (within reasonable distance)
                let searchRange = min(transcriptIdx + 10, manuscriptWindow.count)
                if let matchIdx = manuscriptWindow.prefix(searchRange).firstIndex(where: { $0.word == transcriptWord }) {
                    let idf = wordIDF[transcriptWord] ?? 1.0

                    // Only score high-IDF words
                    if idf >= minUsefulIDF {
                        // Bonus for consecutive matches (sequence preservation)
                        if matchIdx == transcriptIdx || matchIdx == transcriptIdx + 1 {
                            consecutiveMatches += 1
                            score += idf * 2.0  // Double weight for sequence match
                        } else {
                            score += idf
                        }
                    }
                }
            }

            // Require at least 3 consecutive matches to consider valid
            if consecutiveMatches >= 3 && score > bestScore {
                bestScore = score
                bestPosition = startPos
            }
        }

        // Need strong evidence to jump
        guard bestScore > 10.0 else {
            logger.info("CATCHUP: No strong match found (best score: \(String(format: "%.1f", bestScore))), starting from beginning")
            return
        }

        // Seed at the matched position
        if bestPosition < manuscriptWords.count {
            let bestChunk = manuscriptWords[bestPosition].chunkIndex
            self.currentPosition = bestPosition
            self.currentChunkIndex = bestChunk

            // Reset hysteresis counters to commit to this position
            self.pendingChunkIndex = bestChunk
            self.pendingChunkCount = chunkChangeThreshold  // Already "confirmed"

            // CRITICAL: Clear old state from failed attempts at beginning
            // Otherwise UI shows highlights at BOTH the start and the catchup position
            self.confirmedMatchedPositions.removeAll()
            self.matchChain.removeAll()

            // Seed match chain with actual aligned words from this position
            let windowSize = min(30, manuscriptWords.count - bestPosition)
            let manuscriptWindow = Array(manuscriptWords[bestPosition..<(bestPosition + windowSize)])

            for (idx, word) in searchWindow.prefix(10).enumerated() {
                if let matchIdx = manuscriptWindow.firstIndex(where: { $0.word == word }) {
                    let manuscriptPos = bestPosition + matchIdx
                    let idf = self.wordIDF[word] ?? 1.0
                    self.matchChain.append((idx, manuscriptPos, idf, true))
                    self.confirmedMatchedPositions.insert(manuscriptPos)
                    self.lastConsecutiveMatchTranscriptIndex = idx
                }
            }

            logger.info("CATCHUP: Jumped to chunk \(bestChunk) (score \(String(format: "%.1f", bestScore)), pos \(bestPosition))")
        }
    }

    /// Try to fit a transcript word into the manuscript sequence
    private func tryToFitWord(_ word: String, transcriptIndex: Int) {
        guard let positions = wordToPositions[word] else { return }
        let idf = wordIDF[word] ?? 1.0

        // Only match "useful" words (skip common words)
        guard idf >= minUsefulIDF else { return }

        // Calculate expected position based on last match
        let expectedPos: Int
        let maxDeviation: Int

        if let lastMatch = matchChain.last {
            // We have a previous match - expect next word to be close
            let transcriptGap = transcriptIndex - lastMatch.transcriptIndex
            expectedPos = lastMatch.manuscriptPosition + transcriptGap  // Roughly 1:1 mapping

            // After catchup, allow wider search (common words get filtered by IDF anyway)
            // This prevents bouncing when the speaker briefly goes off-script or says filler words
            let baseDeviation = max(10, transcriptGap * 3)
            maxDeviation = transcriptIndex < 50 ? baseDeviation * 3 : baseDeviation  // Extra slack for first 50 words
        } else {
            // No previous match - only look at very beginning of manuscript
            // This prevents jumping ahead before we've established position
            expectedPos = 0
            maxDeviation = 100  // Only match in first 100 words initially
        }

        // Find position closest to expected, within deviation limit
        var bestPosition: Int? = nil
        var bestDistance = Int.max

        for pos in positions {
            let distance = abs(pos - expectedPos)

            // Must be within allowed deviation
            guard distance <= maxDeviation else { continue }

            if distance < bestDistance {
                bestDistance = distance
                bestPosition = pos
            }
        }

        // If we found a valid match, add to chain
        if let pos = bestPosition {
            // Check if this is consecutive with the last match
            // STRICT consecutive: transcript advances 1-3 words, manuscript advances by similar small amount
            // This prevents scattered matches from being called "consecutive"
            var isConsecutive = false
            if let lastMatch = matchChain.last {
                let transcriptDiff = transcriptIndex - lastMatch.transcriptIndex
                let manuscriptDiff = pos - lastMatch.manuscriptPosition
                // Consecutive: transcript moved 1-3 words, manuscript moved 1-5 words forward
                // (Allow a bit more slack for common words filtered by IDF)
                // Both must advance (not stay same or go backward)
                if transcriptDiff >= 1 && transcriptDiff <= 3 &&
                   manuscriptDiff >= 1 && manuscriptDiff <= 5 {
                    isConsecutive = true
                    // Also mark the previous match as consecutive (it's part of a run now)
                    if !lastMatch.isConsecutive && matchChain.count > 0 {
                        let idx = matchChain.count - 1
                        matchChain[idx].isConsecutive = true
                    }
                    lastConsecutiveMatchTranscriptIndex = transcriptIndex

                    // FILL IN THE GAP: only if manuscript gap roughly matches transcript gap
                    // This prevents highlighting skipped words (e.g., "Pastor" when speaker said "when john asked"
                    // but manuscript has "when Pastor Jon first asked")
                    // Allow up to 3 word difference for natural paraphrasing/filler words
                    if abs(manuscriptDiff - transcriptDiff) <= 3 {
                        for gapPos in (lastMatch.manuscriptPosition + 1)..<pos {
                            confirmedMatchedPositions.insert(gapPos)
                        }
                    }
                }
            }

            matchChain.append((transcriptIndex, pos, idf, isConsecutive))

            // Keep chain bounded
            if matchChain.count > maxChainLength {
                matchChain.removeFirst()
            }
        }
    }

    /// Estimate current position from recent matches
    private func updatePositionFromChain() {
        // Use recent matches, but ONLY consecutive ones matter for position
        let recentMatches = Array(matchChain.suffix(chainWindowForPosition))
        let consecutiveMatches = recentMatches.filter { $0.isConsecutive }

        // Check if we've gone too long without new consecutive matches (off-script)
        let currentTranscriptIndex = transcriptWords.count - 1
        let wordsSinceLastConsecutive = currentTranscriptIndex - lastConsecutiveMatchTranscriptIndex

        // If 30+ words without a consecutive match, we're off-script
        if wordsSinceLastConsecutive > 30 {
            isOffScript = true
            matchConfidence = max(0, matchConfidence - 0.1)
            logger.info("OFF-SCRIPT: \(wordsSinceLastConsecutive) words since last consecutive match")
            return
        } else if wordsSinceLastConsecutive < 15 {
            // Only clear off-script when we've had recent consecutive matches
            isOffScript = false
        }

        // Need at least 5 consecutive matches (a strong run) to have confidence
        guard consecutiveMatches.count >= 5 else {
            matchConfidence = max(0, matchConfidence - 0.1)
            if consecutiveMatches.count > 0 {
                logger.info("Weak signal: only \(consecutiveMatches.count) consecutive matches (need 5)")
            }
            return
        }

        // Only add CONSECUTIVE matches to confirmed set if they're part of a strong run
        // Require at least 3 consecutive matches in a row to start highlighting
        // This prevents isolated 1-2 word matches from being highlighted
        if consecutiveMatches.count >= 3 {
            for match in consecutiveMatches {
                confirmedMatchedPositions.insert(match.manuscriptPosition)
            }
        }

        // Calculate position using MEDIAN of consecutive matches only
        let sortedPositions = consecutiveMatches.map { $0.manuscriptPosition }.sorted()
        let medianPosition = sortedPositions[sortedPositions.count / 2]

        // Update internal position estimate
        currentPosition = medianPosition

        // Derive what chunk this position is in
        var derivedChunkIndex = 0
        if medianPosition < manuscriptWords.count {
            derivedChunkIndex = manuscriptWords[medianPosition].chunkIndex
        }

        // HYSTERESIS: Don't change chunk immediately - need sustained evidence
        // NEVER go backward unless we have overwhelming evidence (very rare)
        if derivedChunkIndex != currentChunkIndex {
            // Going backward requires much stronger evidence
            let threshold = derivedChunkIndex < currentChunkIndex ? chunkChangeThreshold * 2 : chunkChangeThreshold

            if derivedChunkIndex == pendingChunkIndex {
                pendingChunkCount += 1
            } else {
                pendingChunkIndex = derivedChunkIndex
                pendingChunkCount = 1
            }

            // Only actually change chunk after threshold consecutive updates
            if pendingChunkCount >= threshold {
                let oldChunk = currentChunkIndex
                currentChunkIndex = derivedChunkIndex
                pendingChunkCount = 0
                logger.info("CHUNK: \(oldChunk) → \(self.currentChunkIndex) (pos \(medianPosition), \(consecutiveMatches.count) consecutive)")
            } else {
                logger.info("Pending chunk \(derivedChunkIndex) (\(self.pendingChunkCount)/\(threshold)), staying at \(self.currentChunkIndex)")
            }
        } else {
            // We're at the current chunk - reset pending
            pendingChunkCount = 0
        }

        // Calculate confidence based on consecutive match density
        let recentTranscriptSpan = (recentMatches.last?.transcriptIndex ?? 0) - (recentMatches.first?.transcriptIndex ?? 0) + 1
        let consecutiveDensity = Double(consecutiveMatches.count) / Double(max(recentTranscriptSpan, 1))

        // More consecutive matches = higher confidence
        matchConfidence = min(1.0, consecutiveDensity * 2.0)

        // Log periodically
        if transcriptWords.count % 20 == 0 {
            let chainPreview = consecutiveMatches.suffix(5).map { "\($0.manuscriptPosition)" }.joined(separator: ",")
            logger.info("Chain: [\(chainPreview)] → median \(medianPosition) chunk \(self.currentChunkIndex) (\(consecutiveMatches.count) consecutive)")
        }
    }

    // MARK: - Helpers

    private func normalizeWord(_ word: String) -> String {
        let cleaned = word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3 else { return "" }
        return cleaned
    }

    private func normalizeText(_ text: String) -> [String] {
        // Include ALL words in the index (even short ones like "to", "a")
        // IDF filtering handles which words are used for matching
        // Short words still get highlighted via gap-filling
        text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func resetTracking() {
        currentPosition = 0
        currentChunkIndex = 0
        matchChain.removeAll()
        confirmedMatchedPositions.removeAll()
        lastProcessedWordCount = 0
        transcriptWords.removeAll()
        matchConfidence = 0.0
        isOffScript = false
        pendingChunkIndex = 0
        pendingChunkCount = 0
        lastConsecutiveMatchTranscriptIndex = 0
    }

    func reset() {
        manuscriptWords.removeAll()
        wordToPositions.removeAll()
        wordIDF.removeAll()
        totalChunks = 0
        resetTracking()
    }

    /// Get all confirmed matched words grouped by chunk (for highlighting in UI)
    func getMatchedWordsByChunk() -> [Int: [String]] {
        var result: [Int: [String]] = [:]

        // Use all confirmed matched positions (cumulative)
        for pos in confirmedMatchedPositions {
            guard pos >= 0 && pos < manuscriptWords.count else { continue }

            let mw = manuscriptWords[pos]
            result[mw.chunkIndex, default: []].append(mw.word)
        }

        return result
    }
}
