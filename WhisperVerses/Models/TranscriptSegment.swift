import Foundation

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isConfirmed: Bool
    let detectedReferences: [BibleReference]

    init(text: String, startTime: TimeInterval = 0, endTime: TimeInterval = 0, isConfirmed: Bool = true, detectedReferences: [BibleReference] = []) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isConfirmed = isConfirmed
        self.detectedReferences = detectedReferences
    }

    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
