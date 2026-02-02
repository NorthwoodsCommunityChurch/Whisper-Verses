import Foundation
import AppKit

/// Captures slide images from Pro7 API and saves them as transparent PNGs.
/// Used by the verse detection pipeline: when a verse is detected and its slide
/// is located via PresentationIndexer, this service fetches the thumbnail,
/// converts it to PNG, and saves it to the output folder.
struct SlideImageCapture {

    /// Capture a verse's slide image from Pro7 and save as PNG.
    /// Returns the saved file URL and filename on success.
    static func captureAndSave(
        api: ProPresenterAPI,
        presentationUUID: String,
        slideIndex: Int,
        reference: BibleReference,
        sequenceNumber: Int,
        outputFolder: URL
    ) async throws -> (fileURL: URL, filename: String) {
        // 1. Get slide image from Pro7 at full 1080p resolution
        let imageData = try await api.getSlideImage(
            presentationUUID: presentationUUID,
            slideIndex: slideIndex,
            quality: 1920
        )

        // 2. Convert to PNG (handles both TIFF and JPEG source formats)
        guard let pngData = ImageConverter.toPNG(imageData) else {
            throw CaptureError.conversionFailed
        }

        // 3. Save with sequential naming: "001_John_3_16.png"
        let filename = String(format: "%03d_%@.png", sequenceNumber, reference.filenameString)
        let fileURL = outputFolder.appendingPathComponent(filename)
        try pngData.write(to: fileURL)

        return (fileURL, filename)
    }

    enum CaptureError: Error, LocalizedError {
        case noImageData
        case conversionFailed
        case verseNotIndexed

        var errorDescription: String? {
            switch self {
            case .noImageData: return "No image data received from ProPresenter"
            case .conversionFailed: return "Failed to convert slide image to PNG"
            case .verseNotIndexed: return "Verse not found in ProPresenter library"
            }
        }
    }
}
