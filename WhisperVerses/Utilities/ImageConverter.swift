import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

    /// Remove a magenta chroma background from a Pro7 slide and produce true alpha.
    ///
    /// Pro7's thumbnail API never returns alpha=0 pixels — it always renders the slide
    /// onto an opaque canvas. To get real transparency, set the Pro7 slide template
    /// background to pure magenta (#FF00FF), then key it out here.
    ///
    /// Calibration note: although the Pro7 template uses `#FF00FF`, Pro7's render
    /// pipeline outputs the chroma as `(255, 64, 255)` — there's a consistent green
    /// tint, likely from color management. The keyer is calibrated to that real
    /// observed value, not the nominal one.
    ///
    /// Algorithm: per pixel, compute how much chroma is present, then unmix it
    /// using the standard alpha-compositing inverse:
    ///     P = α · F + (1 − α) · C        (compositing)
    ///     F = (P − (1 − α) · C) / α      (recovered foreground, unpremultiplied)
    ///
    /// Anti-aliased edges become correctly partial-alpha with their foreground
    /// color preserved (no fringe). Foreground is assumed to contain negligible
    /// chroma — light text (white, cream, gold) is fine.
    static func keyOutMagenta(_ imageData: Data) -> Data? {
        // Calibrated chroma color as Pro7 actually renders it (not pure #FF00FF).
        let cR = 255, cG = 64, cB = 255
        let mScale = 255 - cG   // 191

        // Decode incoming bytes to a CGImage so we get a deterministic source.
        guard let provider = CGDataProvider(data: imageData as CFData),
              let sourceCG = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
                ?? makeCGImage(from: imageData) else {
            return nil
        }

        let width  = sourceCG.width
        let height = sourceCG.height
        let bytesPerRow = width * 4

        // Allocate our own buffer so we control the pixel layout completely.
        let pixelCount = width * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount * 4)
        defer { buffer.deallocate() }
        buffer.update(repeating: 0, count: pixelCount * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // CGContext requires premultiplied alpha for RGBA8. We'll draw the source in,
        // then walk pixels treating them as premultiplied (which is fine since the
        // source has alpha=255 throughout — premul vs non-premul values are identical).
        guard let ctx = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Per-pixel keying. Source alpha is 255 throughout, so values in the buffer
        // already match the unpremultiplied RGB. We compute new alpha from how much
        // chroma is present, then unmix the chroma contribution from R, G, B.
        for i in 0..<pixelCount {
            let off = i * 4
            let r = Int(buffer[off])
            let g = Int(buffer[off + 1])
            let b = Int(buffer[off + 2])

            let m = max(0, (r + b) / 2 - g)
            let alpha = max(0, min(255, 255 - (m * 255) / mScale))

            if alpha == 0 {
                // Premultiplied alpha: zero RGB so the PNG decoder shows clean transparency.
                buffer[off]     = 0
                buffer[off + 1] = 0
                buffer[off + 2] = 0
                buffer[off + 3] = 0
            } else if alpha < 255 {
                let inv = 255 - alpha
                // Recovered (unpremultiplied) foreground RGB
                let fr = (r * 255 - inv * cR) / alpha
                let fg = (g * 255 - inv * cG) / alpha
                let fb = (b * 255 - inv * cB) / alpha
                let frC = max(0, min(255, fr))
                let fgC = max(0, min(255, fg))
                let fbC = max(0, min(255, fb))
                // Re-premultiply for the CGContext's premultipliedLast format.
                buffer[off]     = UInt8((frC * alpha) / 255)
                buffer[off + 1] = UInt8((fgC * alpha) / 255)
                buffer[off + 2] = UInt8((fbC * alpha) / 255)
                buffer[off + 3] = UInt8(alpha)
            } else {
                // Fully opaque foreground — keep RGB as-is, force alpha to 255.
                buffer[off + 3] = 255
            }
        }

        guard let outCG = ctx.makeImage() else { return nil }
        return encodePNG(cgImage: outCG)
    }

    // MARK: - Helpers

    /// Generic CGImage decoder for non-PNG sources (TIFF, JPEG, etc.) just in case.
    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Encode a CGImage as PNG, preserving its alpha channel.
    private static func encodePNG(cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        let utType = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(mutableData, utType, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }
}
