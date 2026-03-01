import Foundation

/// A word with its timing from WhisperKit
struct TimedWord {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    let probability: Float
}

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isConfirmed: Bool
    let detectedReferences: [BibleReference]
    let words: [TimedWord]

    init(text: String, startTime: TimeInterval = 0, endTime: TimeInterval = 0, isConfirmed: Bool = true, detectedReferences: [BibleReference] = [], words: [TimedWord] = []) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isConfirmed = isConfirmed
        self.detectedReferences = detectedReferences
        self.words = words
    }

    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
