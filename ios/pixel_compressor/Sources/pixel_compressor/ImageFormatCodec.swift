import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Format <-> UTType mapping and CGImage encode helper shared by
/// `ImageEngine` and `ThumbnailEngine`. `CGImage`-only, no UIKit, so this
/// file works unmodified on macOS.
enum ImageFormatCodec {
  /// Resolves the UTType identifier to encode with. Throws
  /// `unsupported_codec` for WebP — iOS/macOS's ImageIO can decode WebP but
  /// has no WebP encoder, so requesting WebP *output* is always rejected
  /// here, before any decode work happens; it must never silently fall
  /// back to another format.
  static func utType(for format: ImageFormatWire) throws -> CFString {
    switch format {
    case .jpeg:
      return UTType.jpeg.identifier as CFString
    case .png:
      return UTType.png.identifier as CFString
    case .heic:
      return "public.heic" as CFString
    case .webp:
      throw PixelCompressorError.unsupportedCodec(
        "WebP encoding isn't supported on iOS/macOS: ImageIO can decode WebP but has no WebP encoder"
      )
    }
  }

  static func fileExtension(for format: ImageFormatWire) -> String {
    switch format {
    case .jpeg: return "jpg"
    case .png: return "png"
    case .webp: return "webp"
    case .heic: return "heic"
    }
  }

  static func formatName(for format: ImageFormatWire) -> String {
    switch format {
    case .jpeg: return "jpeg"
    case .png: return "png"
    case .webp: return "webp"
    case .heic: return "heic"
    }
  }

  /// Best-effort format inference from a source file's UTType, used for
  /// "keep the source's own format" (no explicit `format` in the request)
  /// and by `MediaInfoEngine`.
  static func format(forPathExtension ext: String) -> ImageFormatWire {
    switch ext.lowercased() {
    case "png": return .png
    case "heic", "heif": return .heic
    case "webp": return .webp
    default: return .jpeg
    }
  }

  /// Encodes `image` to `url` in `format` at `quality` (1-100, mapped to
  /// 0.0-1.0; ignored for PNG, which is always lossless).
  /// `properties`, when non-nil, are written verbatim as image properties
  /// (used to copy/adjust EXIF metadata for `ExifPolicy.keep`); `nil`
  /// writes no extra metadata (`ExifPolicy.strip`).
  static func encode(
    image: CGImage,
    to url: URL,
    format: ImageFormatWire,
    quality: Int,
    properties: [CFString: Any]? = nil
  ) throws {
    let type = try utType(for: format)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
      throw PixelCompressorError.encodingError(
        "Could not create image destination for \(url.lastPathComponent)")
    }
    var options: [CFString: Any] = properties ?? [:]
    if format != .png {
      options[kCGImageDestinationLossyCompressionQuality] = Double(max(1, min(quality, 100))) / 100.0
    }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw PixelCompressorError.encodingError(
        "Failed to finalize image encode for \(url.lastPathComponent)")
    }
  }

  /// Draws `image` into a new `CGContext` rotated clockwise by `degrees`
  /// (0/90/180/270), returning an upright `CGImage` with the rotation
  /// baked into the pixels. Used whenever pixels must be physically
  /// rotated rather than relying on an EXIF tag or transform metadata.
  static func rotate(_ image: CGImage, byDegrees degrees: Int) throws -> CGImage {
    let normalized = RotationMath.normalize(degrees)
    guard normalized != 0 else { return image }

    let swapDims = (normalized == 90 || normalized == 270)
    let width = swapDims ? image.height : image.width
    let height = swapDims ? image.width : image.height

    // Always draw into a standard 8-bit RGBA context rather than trying to
    // reuse the source CGImage's own bitmapInfo: source images can be
    // CMYK, grayscale, indexed, or use alpha/byte-order combinations
    // CGContext doesn't accept directly. `draw(_:in:)` handles the color
    // space conversion for us.
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw PixelCompressorError.encodingError("Could not create rotation context")
    }

    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    // Positive angle here rotates the drawn content clockwise as displayed
    // on screen (CGContext's Y axis points up, so a clockwise on-screen
    // rotation is a negative mathematical angle).
    let radians = -CGFloat(normalized) * .pi / 180
    context.rotate(by: radians)
    context.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    guard let rotated = context.makeImage() else {
      throw PixelCompressorError.encodingError("Could not render rotated image")
    }
    return rotated
  }

  /// Draws `image` scaled to fit within `maxPixelSize` on its longest
  /// edge (aspect ratio preserved), used by `ThumbnailEngine` after
  /// extracting a video frame.
  static func resize(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
    let longestEdge = max(image.width, image.height)
    guard longestEdge > maxPixelSize else { return image }
    let scale = Double(maxPixelSize) / Double(longestEdge)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw PixelCompressorError.encodingError("Could not create resize context")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let resized = context.makeImage() else {
      throw PixelCompressorError.encodingError("Could not render resized image")
    }
    return resized
  }
}
