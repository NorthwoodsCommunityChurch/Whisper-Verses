import Foundation
import SwiftUI

struct DetectedVerse: Identifiable {
    let id = UUID()
    let reference: BibleReference
    let confidence: Confidence
    let detectedAt: Date
    let sourceText: String     // The transcript text that triggered detection
    var status: Status = .detected

    enum Confidence: Comparable {
        case high
        case medium
        case low

        var label: String {
            switch self {
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            }
        }
    }

    enum Status {
        case detected
        case duplicate          // Already captured in this session
        case capturing
        case saved(filename: String)
        case failed(error: String)

        var isSaved: Bool {
            if case .saved = self { return true }
            return false
        }

        var isTerminal: Bool {
            switch self {
            case .saved, .duplicate: return true
            default: return false
            }
        }

        var isDuplicate: Bool {
            if case .duplicate = self { return true }
            return false
        }

        var dotColor: SwiftUI.Color {
            switch self {
            case .duplicate: return .gray
            case .failed: return .red
            case .capturing: return .orange
            default: return .orange
            }
        }
    }
}
