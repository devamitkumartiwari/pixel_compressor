import CoreImage
import ImageIO
import SDWebImageWebPCoder
import UIKit
import UniformTypeIdentifiers

/// pixel_compressor additions: max bounds and exact output size, sent as six
/// trailing ints after the base arguments (0 = unset).
struct ResizeSpec {
    var maxWidth = 0
    var maxHeight = 0
    var exactWidth = 0
    var exactHeight = 0
    /// 0 = stretch, 1 = contain (pad), 2 = cover (crop).
    var fit = 1
    /// ARGB.
    var padColor: UInt32 = 0

    var hasExact: Bool { exactWidth > 0 && exactHeight > 0 }

    init(args: [Any], start: Int) {
        func int(_ i: Int) -> Int {
            let index = start + i
            guard index < args.count, let number = args[index] as? NSNumber else { return 0 }
            return number.intValue
        }
        maxWidth = int(0)
        maxHeight = int(1)
        exactWidth = int(2)
        exactHeight = int(3)
        fit = int(4)
        padColor = UInt32(truncatingIfNeeded: int(5))
    }
}

enum ImageEncoder {
    /// Output format indices, matching `PixelImageFormat` in Dart.
    enum Format: Int {
        case jpeg = 0, png = 1, heic = 2, webp = 3
    }

    // MARK: Decode

    static func decode(_ data: Data) -> UIImage? {
        if isWebP(data) {
            return SDImageWebPCoder.shared.decodedImage(with: data, options: nil)
        }
        return UIImage(data: data)
    }

    static func isWebP(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP"
    }

    // MARK: Compress

    static func compress(_ image: UIImage, minWidth: Int, minHeight: Int, quality: Int,
                         rotate: Int, format: Int, resize: ResizeSpec) -> Data? {
        ImageCompressHandler.log(
            "width = \(image.size.width), height = \(image.size.height), minWidth = \(minWidth), minHeight = \(minHeight), format = \(format)")
        let prepared = scaleRotateAndFit(image, minWidth: minWidth, minHeight: minHeight,
                                         rotate: rotate, resize: resize)
        return encode(prepared, quality: Float(quality), format: format)
    }

    /// Scale-then-rotate, plus max bounds and the final exact-size
    /// pass. With an exact size, pre-scale so the image just covers the target
    /// (in pre-rotation axes) and let `fitted` produce W×H after rotation.
    static func scaleRotateAndFit(_ image: UIImage, minWidth: Int, minHeight: Int,
                                  rotate: Int, resize: ResizeSpec) -> UIImage {
        var image = image
        if resize.hasExact {
            let quarterTurn = ((rotate % 360) + 360) % 180 == 90
            let boundW = quarterTurn ? resize.exactHeight : resize.exactWidth
            let boundH = quarterTurn ? resize.exactWidth : resize.exactHeight
            image = image.scaled(minWidth: CGFloat(boundW), minHeight: CGFloat(boundH))
        } else {
            image = image.scaled(minWidth: CGFloat(minWidth), minHeight: CGFloat(minHeight),
                                 maxWidth: CGFloat(resize.maxWidth), maxHeight: CGFloat(resize.maxHeight))
        }
        if rotate % 360 != 0 {
            image = image.rotated(by: CGFloat(rotate))
        }
        if resize.hasExact {
            image = image.fitted(width: resize.exactWidth, height: resize.exactHeight,
                                 fit: resize.fit, padColor: resize.padColor)
        }
        return image
    }

    // MARK: Encode

    static func encode(_ image: UIImage, quality: Float, format: Int) -> Data? {
        switch Format(rawValue: format) {
        case .heic:
            // ImageIO first: in memory, and it accepts the inputs (alpha,
            // extended range) that make CIContext's HEIF writer fail with
            // kCMPhotoError_InvalidData. CIContext stays as the fallback.
            if let data = heicWithImageIO(image, quality: quality), !data.isEmpty {
                return data
            }
            return heicWithCIContext(image, quality: quality)
        case .webp:
            return SDImageWebPCoder.shared.encodedData(
                with: image, format: .webP,
                options: [.encodeCompressionQuality: quality / 100])
        case .png:
            return image.pngData()
        default: // jpeg
            return image.jpegData(compressionQuality: CGFloat(quality) / 100)
        }
    }

    private static func heicWithImageIO(_ image: UIImage, quality: Float) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality / 100] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            ImageCompressHandler.log("ImageIO HEIC encode failed, falling back to CIContext")
            return nil
        }
        return output as Data
    }

    private static func heicWithCIContext(_ image: UIImage, quality: Float) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).heic")
        // Always attempt cleanup; the file may be missing or partial on failure.
        defer { try? FileManager.default.removeItem(at: url) }
        let colorSpace = ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality / 100]
        do {
            try CIContext().writeHEIFRepresentation(of: ciImage, to: url, format: .ARGB8,
                                                    colorSpace: colorSpace, options: options)
            return try Data(contentsOf: url)
        } catch {
            ImageCompressHandler.log("HEIC write failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Metadata

    /// Copies every top-level image property dict (EXIF, TIFF, GPS, IPTC,
    /// PNG, maker notes, …) from `source` into `encoded` via CGImageSource →
    /// CGImageDestination, so keys a typed model would drop (e.g. TIFF
    /// DateTime on iOS screenshots) survive. Returns nil when ImageIO can't
    /// author the container (e.g. WebP); callers then keep the encoded bytes.
    static func copyingMetadata(from source: Data, into encoded: Data) -> Data? {
        guard !source.isEmpty, !encoded.isEmpty else { return nil }
        guard let sourceRef = CGImageSourceCreateWithData(source as CFData, nil),
              let rawProps = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any] else {
            ImageCompressHandler.log("keepExif: could not read source metadata (unsupported container)")
            return nil
        }
        guard let encodedRef = CGImageSourceCreateWithData(encoded as CFData, nil),
              let encodedType = CGImageSourceGetType(encodedRef) else {
            return nil
        }
        let merged = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(merged as CFMutableData, encodedType, 1, nil) else {
            ImageCompressHandler.log("keepExif: no CGImageDestination for \(encodedType); keeping bytes without metadata")
            return nil
        }

        // The pipeline scales and (optionally) rotates before re-encoding, so
        // the source's pixel size and orientation no longer describe the
        // output. Drop keys that describe the source's pixel buffer (colour
        // profile, depth, alpha, indexed/float): a stale Display-P3
        // ProfileName on an sRGB output makes colour-managed viewers apply the
        // wrong transform, and HasAlpha from a PNG source contradicts a JPEG.
        var props = rawProps
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyFileSize,
                    kCGImagePropertyProfileName, kCGImagePropertyColorModel, kCGImagePropertyDepth,
                    kCGImagePropertyHasAlpha, kCGImagePropertyIsFloat, kCGImagePropertyIsIndexed] {
            props.removeValue(forKey: key)
        }
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            props[kCGImagePropertyExifDictionary] = exif
        }

        CGImageDestinationAddImageFromSource(destination, encodedRef, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            ImageCompressHandler.log("keepExif: CGImageDestinationFinalize failed")
            return nil
        }
        // Finalize can succeed while AddImageFromSource silently no-ops.
        return merged.length > 0 ? merged as Data : nil
    }

    // MARK: Diagnostics

    /// MIME type from magic bytes; only used in error messages.
    static func mimeType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x42, 0x4D]) { return "image/x-ms-bmp" }
        if starts(Array("GIF".utf8)) { return "image/gif" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts(Array("8BPS".utf8)) { return "image/psd" }
        if starts(Array("RIFF".utf8)) { return "image/webp" }
        if starts([0x00, 0x00, 0x01, 0x00]) { return "image/vnd.microsoft.icon" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts(Array("ftyp".utf8), at: 4), bytes.count >= 12 {
            switch String(bytes: bytes[8..<12], encoding: .ascii) {
            case "heic", "heix", "hevc": return "image/heic"
            case "mif1", "msf1": return "image/heif"
            case "avif", "avis": return "image/avif"
            default: break
            }
        }
        return "application/octet-stream"
    }
}
