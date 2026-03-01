import Foundation
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "ManuscriptSession")

final class ManuscriptSession {
    private(set) var chunks: [String] = []
    private(set) var currentPosition: Int = 0
    private(set) var isOffScript: Bool = false
    private(set) var confidence: Double = 0.0

    private let lock = NSLock()
    private let matcher: EmbeddingMatcher

    // Throttle embedding inference to every 2 seconds
    private var lastEmbeddingTime: Date = .distantPast
    private let embeddingInterval: TimeInterval = 2.0

    init(matcher: EmbeddingMatcher) {
        self.matcher = matcher
    }

    func loadManuscript(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        chunks = Self.parseIntoChunks(text)
        currentPosition = 0
        isOffScript = false
        confidence = 0.0

        logger.info("Loaded manuscript with \(self.chunks.count) chunks")
    }

    /// Build embedding index for loaded chunks (async, may take a few seconds)
    func buildEmbeddingIndex() async {
        let chunkTexts: [String]
        lock.lock()
        chunkTexts = chunks
        lock.unlock()

        await matcher.buildIndex(from: chunkTexts)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        chunks.removeAll()
        currentPosition = 0
        isOffScript = false
        confidence = 0.0
        matcher.reset()
    }

    /// Called every 150ms from broadcast loop — returns cached state, no heavy computation
    func processTranscript(confirmedText: String, hypothesis: String, audioLevel: Float) -> SessionUpdate {
        lock.lock()
        defer { lock.unlock() }

        guard !chunks.isEmpty else {
            return SessionUpdate(
                currentPosition: 0,
                confidence: 0,
                isOffScript: false,
                confirmedTranscript: "",
                chunks: [],
                matchedWords: [:]
            )
        }

        // Read latest position from matcher
        currentPosition = matcher.currentChunkIndex
        confidence = matcher.matchConfidence
        isOffScript = matcher.isOffScript

        return buildSessionUpdate(confirmedText: confirmedText)
    }

    /// Run embedding-based matching (called async from background Task, throttled)
    func updateEmbeddingMatch(transcript: String) async {
        let now = Date()
        guard now.timeIntervalSince(lastEmbeddingTime) >= embeddingInterval else { return }
        lastEmbeddingTime = now

        guard matcher.isModelLoaded, matcher.isIndexBuilt else { return }
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await matcher.findPosition(transcript: transcript)
    }

    var currentSnippet: String {
        lock.lock()
        defer { lock.unlock() }

        guard currentPosition < chunks.count else { return "" }
        return chunks[currentPosition]
    }

    // MARK: - Private

    private func buildSessionUpdate(confirmedText: String) -> SessionUpdate {
        SessionUpdate(
            currentPosition: currentPosition,
            confidence: confidence,
            isOffScript: isOffScript,
            confirmedTranscript: confirmedText,
            chunks: chunks.enumerated().map { index, chunk in
                ChunkState(
                    id: index,
                    text: chunk,
                    status: statusForChunk(at: index)
                )
            },
            matchedWords: [:]  // Embedding matching operates at chunk level
        )
    }

    private func statusForChunk(at index: Int) -> ChunkStatus {
        if index < currentPosition {
            return .past
        } else if index == currentPosition {
            return .current
        } else {
            return .future
        }
    }

    // MARK: - Chunk Parsing

    private static let targetChunkSize = 5

    static func parseIntoChunks(_ text: String) -> [String] {
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else { return [] }

        var chunks: [String] = []
        var currentSentences: [String] = []

        for sentence in sentences {
            currentSentences.append(sentence)
            if currentSentences.count >= targetChunkSize {
                chunks.append(currentSentences.joined(separator: " "))
                currentSentences.removeAll()
            }
        }

        if !currentSentences.isEmpty {
            chunks.append(currentSentences.joined(separator: " "))
        }

        return chunks
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let terminators: Set<Character> = [".", "!", "?"]

        for char in text {
            current.append(char)
            if terminators.contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }

        return sentences
    }
}

// MARK: - Data Types

enum ChunkStatus: String, Codable {
    case past
    case current
    case future
}

struct ChunkState: Codable {
    let id: Int
    let text: String
    let status: ChunkStatus
}

struct SessionUpdate: Codable {
    let currentPosition: Int
    let confidence: Double
    let isOffScript: Bool
    let confirmedTranscript: String
    let chunks: [ChunkState]
    let matchedWords: [String: [String]]

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
