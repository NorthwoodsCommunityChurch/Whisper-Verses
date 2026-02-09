import Foundation
import OSLog
import Compression

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "DocumentParser")

enum DocumentParser {
    /// Parse plain text file
    static func parsePlainText(_ data: Data) -> String? {
        // Try UTF-8 first
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        // Fallback to other encodings
        for encoding: String.Encoding in [.utf16, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        logger.error("Failed to decode plain text file")
        return nil
    }

    /// Parse .docx file (ZIP archive containing XML)
    static func parseDocx(_ data: Data) -> String? {
        // .docx is a ZIP archive
        guard let files = unzip(data) else {
            logger.error("Failed to unzip docx file")
            return nil
        }

        // Find word/document.xml
        guard let documentXml = files["word/document.xml"] else {
            logger.error("document.xml not found in docx")
            return nil
        }

        // Parse XML and extract text
        return extractTextFromDocumentXml(documentXml)
    }

    /// Extract text content from Word document.xml
    private static func extractTextFromDocumentXml(_ data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            return nil
        }

        var textParts: [String] = []
        var currentParagraph: [String] = []

        // Simple regex-based extraction of <w:t> elements
        // This handles the common case; a full XML parser would be more robust
        let pattern = #"<w:t[^>]*>([^<]*)</w:t>"#

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(xmlString.startIndex..., in: xmlString)
            let matches = regex.matches(in: xmlString, range: range)

            for match in matches {
                if let textRange = Range(match.range(at: 1), in: xmlString) {
                    let text = String(xmlString[textRange])
                    currentParagraph.append(text)
                }
            }
        }

        // Look for paragraph breaks <w:p>
        let paragraphPattern = #"<w:p[^/]*>"#
        if let paragraphRegex = try? NSRegularExpression(pattern: paragraphPattern) {
            let range = NSRange(xmlString.startIndex..., in: xmlString)
            let paragraphMatches = paragraphRegex.matches(in: xmlString, range: range)

            // Re-parse with paragraph awareness
            textParts.removeAll()
            currentParagraph.removeAll()

            var lastEnd = xmlString.startIndex

            for pMatch in paragraphMatches {
                if let pRange = Range(pMatch.range, in: xmlString) {
                    // Extract text from previous paragraph section
                    let section = String(xmlString[lastEnd..<pRange.lowerBound])
                    let sectionText = extractTextElements(from: section)
                    if !sectionText.isEmpty {
                        textParts.append(sectionText)
                    }
                    lastEnd = pRange.upperBound
                }
            }

            // Handle remaining content
            let finalSection = String(xmlString[lastEnd...])
            let finalText = extractTextElements(from: finalSection)
            if !finalText.isEmpty {
                textParts.append(finalText)
            }
        }

        let result = textParts.joined(separator: "\n\n")
        logger.info("Extracted \(result.count) characters from docx")
        return result.isEmpty ? nil : result
    }

    /// Extract text from <w:t> elements in a string
    private static func extractTextElements(from xml: String) -> String {
        var texts: [String] = []

        let pattern = #"<w:t[^>]*>([^<]*)</w:t>"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(xml.startIndex..., in: xml)
            let matches = regex.matches(in: xml, range: range)

            for match in matches {
                if let textRange = Range(match.range(at: 1), in: xml) {
                    let text = String(xml[textRange])
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&apos;", with: "'")
                    texts.append(text)
                }
            }
        }

        return texts.joined()
    }

    /// Unzip data into dictionary of filename -> data
    private static func unzip(_ data: Data) -> [String: Data]? {
        // Simple ZIP parser - handles the common case for .docx files
        var files: [String: Data] = [:]

        // ZIP local file header signature: 0x04034b50 (little-endian)
        let localFileHeaderSig: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        let sigData = Data(localFileHeaderSig)

        var offset = 0
        while offset < data.count - 30 {
            // Find next local file header
            let searchRange = data.index(data.startIndex, offsetBy: offset)..<data.endIndex
            guard let headerRange = data[searchRange].range(of: sigData) else {
                break
            }

            let headerStart = data.distance(from: data.startIndex, to: headerRange.lowerBound)

            // Parse header
            guard headerStart + 30 <= data.count else { break }

            let compressionMethod = UInt16(data[headerStart + 8]) | (UInt16(data[headerStart + 9]) << 8)
            let compressedSize = UInt32(data[headerStart + 18]) | (UInt32(data[headerStart + 19]) << 8) |
                                 (UInt32(data[headerStart + 20]) << 16) | (UInt32(data[headerStart + 21]) << 24)
            let uncompressedSize = UInt32(data[headerStart + 22]) | (UInt32(data[headerStart + 23]) << 8) |
                                   (UInt32(data[headerStart + 24]) << 16) | (UInt32(data[headerStart + 25]) << 24)
            let fileNameLength = UInt16(data[headerStart + 26]) | (UInt16(data[headerStart + 27]) << 8)
            let extraFieldLength = UInt16(data[headerStart + 28]) | (UInt16(data[headerStart + 29]) << 8)

            let fileNameStart = headerStart + 30
            let fileNameEnd = fileNameStart + Int(fileNameLength)

            guard fileNameEnd <= data.count else { break }

            let fileNameData = data[fileNameStart..<fileNameEnd]
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                offset = fileNameEnd + Int(extraFieldLength) + Int(compressedSize)
                continue
            }

            let contentStart = fileNameEnd + Int(extraFieldLength)
            let contentEnd = contentStart + Int(compressedSize)

            guard contentEnd <= data.count else { break }

            let compressedData = data[contentStart..<contentEnd]

            // Decompress if needed
            if compressionMethod == 0 {
                // Stored (no compression)
                files[fileName] = Data(compressedData)
            } else if compressionMethod == 8 {
                // Deflate
                if let decompressed = decompress(Data(compressedData), expectedSize: Int(uncompressedSize)) {
                    files[fileName] = decompressed
                }
            }

            offset = contentEnd
        }

        return files.isEmpty ? nil : files
    }

    /// Decompress deflate data
    private static func decompress(_ data: Data, expectedSize: Int) -> Data? {
        var decompressed = Data(count: expectedSize)

        let result = decompressed.withUnsafeMutableBytes { destPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        return result > 0 ? decompressed.prefix(result) : nil
    }
}
