import Foundation
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "ManuscriptSession")

final class ManuscriptSession {
    private(set) var chunks: [ManuscriptChunk] = []
    private(set) var currentPosition: Int = 0
    private(set) var isOffScript: Bool = false
    private(set) var confidence: Double = 0.0

    private var lastMatchTime: Date = Date()
    private var manuscriptText: String = ""

    private let offScriptThreshold: TimeInterval = 12.0
    private let audioThreshold: Float = 0.02

    func loadManuscript(_ text: String) {
        manuscriptText = text
        chunks = ManuscriptMatcher.parseIntoChunks(text)
        currentPosition = 0
        isOffScript = false
        confidence = 0.0
        lastMatchTime = Date()

        logger.info("Loaded manuscript with \(self.chunks.count) chunks")
    }

    func reset() {
        chunks.removeAll()
        manuscriptText = ""
        currentPosition = 0
        isOffScript = false
        confidence = 0.0
    }

    func processTranscript(confirmedText: String, hypothesis: String, audioLevel: Float) -> SessionUpdate {
        guard !chunks.isEmpty else {
            return SessionUpdate(
                currentPosition: 0,
                confidence: 0,
                isOffScript: false,
                chunks: []
            )
        }

        let fullTranscript = confirmedText + " " + hypothesis
        let isSpeaking = audioLevel > audioThreshold

        // Find best matching chunk (only search forward)
        let searchRange = currentPosition..<min(currentPosition + 4, chunks.count)
        var bestMatch = (index: currentPosition, score: 0.0)

        for i in searchRange {
            let score = ManuscriptMatcher.matchScore(
                transcript: fullTranscript,
                chunk: chunks[i].normalizedText
            )

            if score > bestMatch.score {
                bestMatch = (i, score)
            }
        }

        // Update position if we found a good match
        if bestMatch.score > 0.4 {
            if bestMatch.index != currentPosition || bestMatch.score > confidence {
                currentPosition = bestMatch.index
                confidence = bestMatch.score
                lastMatchTime = Date()
                isOffScript = false

                logger.debug("Position updated to \(self.currentPosition) with confidence \(String(format: "%.2f", self.confidence))")
            }
        }

        // Check for off-script state
        let timeSinceMatch = Date().timeIntervalSince(lastMatchTime)
        if isSpeaking && timeSinceMatch > offScriptThreshold {
            isOffScript = true
        } else if !isSpeaking || timeSinceMatch < offScriptThreshold / 2 {
            isOffScript = false
        }

        return SessionUpdate(
            currentPosition: currentPosition,
            confidence: confidence,
            isOffScript: isOffScript,
            chunks: chunks.enumerated().map { index, chunk in
                ChunkState(
                    id: index,
                    text: chunk.text,
                    status: statusForChunk(at: index)
                )
            }
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

    var currentSnippet: String {
        guard currentPosition < chunks.count else { return "" }
        return chunks[currentPosition].text
    }
}

// MARK: - Data Types

struct ManuscriptChunk {
    let text: String
    let normalizedText: String
}

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
    let chunks: [ChunkState]

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
