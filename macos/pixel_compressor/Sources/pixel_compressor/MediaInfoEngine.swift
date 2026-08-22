import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Implements `MetadataHostApi.getMediaInfo`. Images are read via
/// `CGImageSource` properties (no decode needed); video via `AVURLAsset`
/// track/format-description inspection.
final class MediaInfoEngine {
  func read(request: MediaInfoRequest) throws -> MediaInfoMessage {
    let path = request.sourcePath
    guard FileManager.default.fileExists(atPath: path) else {
      throw PixelCompressorError.invalidMedia("Source file does not exist: \(path)")
    }
    let url = URL(fileURLWithPath: path)
    let sizeBytes =
      (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0

    if let imageInfo = try? readImageInfo(url: url, sizeBytes: sizeBytes) {
      return imageInfo
    }
    if let videoInfo = try? readVideoInfo(url: url, sizeBytes: sizeBytes) {
      return videoInfo
    }

    throw PixelCompressorError.unsupportedMedia(
      "Source file isn't a readable image or video: \(path)")
  }

  private func readImageInfo(url: URL, sizeBytes: Int64) throws -> MediaInfoMessage {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      throw PixelCompressorError.metadataError("Not a readable image")
    }

    let width = properties[kCGImagePropertyPixelWidth] as? Int
    let height = properties[kCGImagePropertyPixelHeight] as? Int
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let hasExif =
      (properties[kCGImagePropertyExifDictionary] != nil)
      || (properties[kCGImagePropertyGPSDictionary] != nil)
      || (properties[kCGImagePropertyTIFFDictionary] != nil)

    let typeIdentifier = CGImageSourceGetType(source) as String?
    let formatName = imageFormatName(forUTType: typeIdentifier, url: url)

    return MediaInfoMessage(
      mediaType: .image,
      width: width.map { Int64($0) },
      height: height.map { Int64($0) },
      format: formatName,
      sizeBytes: sizeBytes,
      exifPresent: hasExif,
      orientation: Int64(orientation)
    )
  }

  private func readVideoInfo(url: URL, sizeBytes: Int64) throws -> MediaInfoMessage {
    let asset = AVURLAsset(url: url)
    let videoTracks = asset.tracks(withMediaType: .video)
    let audioTracks = asset.tracks(withMediaType: .audio)
    guard !videoTracks.isEmpty else {
      throw PixelCompressorError.metadataError("Not a readable video")
    }
    let videoTrack = videoTracks[0]

    let displaySize = CGRect(origin: .zero, size: videoTrack.naturalSize)
      .applying(videoTrack.preferredTransform)
    let width = Int64(abs(displaySize.width).rounded())
    let height = Int64(abs(displaySize.height).rounded())

    let durationSeconds = asset.duration.seconds
    let durationMs: Int64? = durationSeconds.isFinite ? Int64(durationSeconds * 1000) : nil

    let fps = videoTrack.nominalFrameRate > 0 ? Double(videoTrack.nominalFrameRate) : nil
    let estimatedBitrate = videoTrack.estimatedDataRate > 0 ? Int64(videoTrack.estimatedDataRate) : nil

    let videoCodec = videoTrack.formatDescriptions
      .first
      .map { CMFormatDescriptionGetMediaSubType($0 as! CMFormatDescription) }
      .map(fourCharString(from:))
    let audioCodec = audioTracks.first?.formatDescriptions.first
      .map { CMFormatDescriptionGetMediaSubType($0 as! CMFormatDescription) }
      .map(fourCharString(from:))

    let container = UTType(filenameExtension: url.pathExtension)?.preferredFilenameExtension
      ?? url.pathExtension.lowercased()

    return MediaInfoMessage(
      mediaType: .video,
      width: width,
      height: height,
      format: container,
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      fps: fps,
      bitrateBps: estimatedBitrate,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      container: container,
      hasAudio: !audioTracks.isEmpty
    )
  }

  private func imageFormatName(forUTType typeIdentifier: String?, url: URL) -> String {
    guard let typeIdentifier = typeIdentifier else {
      return ImageFormatCodec.formatName(for: ImageFormatCodec.format(forPathExtension: url.pathExtension))
    }
    if typeIdentifier == (UTType.jpeg.identifier) { return "jpeg" }
    if typeIdentifier == (UTType.png.identifier) { return "png" }
    if typeIdentifier == "public.heic" || typeIdentifier == "public.heif" { return "heic" }
    if typeIdentifier == (UTType.webP.identifier) { return "webp" }
    if typeIdentifier == (UTType.gif.identifier) { return "gif" }
    return ImageFormatCodec.formatName(for: ImageFormatCodec.format(forPathExtension: url.pathExtension))
  }

  private func fourCharString(from code: FourCharCode) -> String {
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF),
      UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF),
      UInt8(code & 0xFF),
    ]
    let scalars = bytes.compactMap { byte -> Character? in
      guard byte >= 0x20, byte < 0x7F else { return nil }
      return Character(UnicodeScalar(byte))
    }
    return scalars.isEmpty ? String(code) : String(scalars).trimmingCharacters(in: .whitespaces)
  }
}
