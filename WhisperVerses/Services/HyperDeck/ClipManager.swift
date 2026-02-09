import Foundation
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "ClipManager")

enum ClipManager {
    /// Save a clip to the desktop clips file for today
    static func saveClip(timecode: String, manuscriptSnippet: String) {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())

        let filename = "Sermon Clips \(dateString).txt"
        let fileURL = desktop.appendingPathComponent(filename)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timestamp = timeFormatter.string(from: Date())

        // Clean up manuscript snippet - keep it reasonable length
        let snippet = manuscriptSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncatedSnippet: String
        if snippet.count > 500 {
            truncatedSnippet = String(snippet.prefix(500)) + "..."
        } else {
            truncatedSnippet = snippet
        }

        let entry = """

        [\(timecode)] \(timestamp)
        "\(truncatedSnippet)"

        ---
        """

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Append to existing file
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                try handle.close()
                logger.info("Clip appended to \(filename)")
            } else {
                // Create new file with header
                let header = "=== Sermon Clips - \(dateString) ===\n"
                let content = header + entry
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                logger.info("Created new clips file: \(filename)")
            }
        } catch {
            logger.error("Failed to save clip: \(error.localizedDescription)")
        }
    }
}
