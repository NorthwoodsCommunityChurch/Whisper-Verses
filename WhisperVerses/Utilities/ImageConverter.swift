import Foundation
import AppKit

struct ImageConverter {
    /// Convert TIFF image data to PNG data, preserving transparency.
    static func tiffToPNG(_ tiffData: Data) -> Data? {
        guard let image = NSImage(data: tiffData),
              let tiffRep = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffRep) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Convert any image data to PNG.
    static func toPNG(_ imageData: Data) -> Data? {
        guard let image = NSImage(data: imageData),
              let tiffRep = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffRep) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
