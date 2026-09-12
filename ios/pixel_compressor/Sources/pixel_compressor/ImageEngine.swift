import CoreGraphics
import Foundation
import ImageIO

/// Implements `ImageHostApi.compressImage`. `CGImage`/`CGImageSource`/
/// `CGImageDestination` only — no UIKit — so this file works unmodified on
/// macOS via the repo's manual-sync copy.
final class ImageEngine {
  private let cacheManager: CacheManager
  private let taskRegistry: TaskRegistry
  private let progressReporter: ProgressReporter

  private enum Constants {
    static let maxAttempts = 8
    static let qualityStep = 15
    static let qualityFloor = 10
    static let resolutionStepFactor = 0.75
    static let minEdgePx = 200
  }

  init(cacheManager: CacheManager, taskRegistry: TaskRegistry, progressReporter: ProgressReporter) {
    self.cacheManager = cacheManager
    self.taskRegistry = taskRegistry
    self.progressReporter = progressReporter
  }

  func compress(request: ImageCompressRequest) throws -> CompressionResultMessage {
    let taskId = request.taskId
    let startTime = Date()

    try checkCancelled(taskId)
    progressReporter.reportProgress(taskId: taskId, stage: .preparing, percent: 0)

    guard FileManager.default.fileExists(atPath: request.sourcePath) else {
      throw PixelCompressorError.invalidMedia("Source file does not exist: \(request.sourcePath)")
    }
    let sourceURL = URL(fileURLWithPath: request.sourcePath)

    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw PixelCompressorError.decodingError("Could not open source image")
    }
    guard CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 else {
      throw PixelCompressorError.unsupportedMedia("Source file isn't a readable image")
    }

    let sourceProperties =
      (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let sourceOrientation = (sourceProperties[kCGImagePropertyOrientation] as? Int) ?? 1
    let sourceOrientationDegrees =
      request.autoCorrectOrientation
      ? RotationMath.degrees(forExifOrientation: sourceOrientation)
      : 0
    let requestedRotation = try RotationMath.requireCardinal(Int(request.rotationDegrees))

    let originalSize =
      (try? FileManager.default.attributesOfItem(atPath: request.sourcePath)[.size] as? Int64) ?? 0

    let sourceExtension = (sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension)
    let outputFormat = request.format ?? ImageFormatCodec.format(forPathExtension: sourceExtension)
    // WebP output is rejected up front, before any decode work, per the
    // hard platform constraint (ImageIO can decode WebP, never encode it).
    _ = try ImageFormatCodec.utType(for: outputFormat)

    try checkCancelled(taskId)
    progressReporter.reportProgress(taskId: taskId, stage: .decoding, percent: 10)

    let requestedMaxWidth = request.maxWidth.map { Int($0) }
    let requestedMaxHeight = request.maxHeight.map { Int($0) }
    let requestedMaxEdge: Int? = {
      switch (requestedMaxWidth, requestedMaxHeight) {
      case let (.some(w), .some(h)): return max(w, h)
      case let (.some(w), .none): return w
      case let (.none, .some(h)): return h
      case (.none, .none): return nil
      }
    }()

    let baseImage = try decodeAndOrient(
      source: source,
      sourceOrientationDegrees: sourceOrientationDegrees,
      requestedRotation: requestedRotation,
      maxEdge: requestedMaxEdge
    )

    let outputURL = try resolveOutputURL(request: request, format: outputFormat)
    try? FileManager.default.removeItem(at: outputURL)

    progressReporter.reportProgress(taskId: taskId, stage: .encoding, percent: 40)

    let properties = exifOutputProperties(
      policy: request.exifPolicy, sourceProperties: sourceProperties)

    if let targetSizeBytes = request.targetSizeBytes {
      try compressToTargetSize(
        taskId: taskId,
        baseImage: baseImage,
        format: outputFormat,
        initialQuality: Int(request.quality),
        targetSizeBytes: Int(targetSizeBytes),
        properties: properties,
        outputURL: outputURL
      )
    } else {
      try ImageFormatCodec.encode(
        image: baseImage,
        to: outputURL,
        format: outputFormat,
        quality: Int(request.quality),
        properties: properties
      )
    }

    try checkCancelled(taskId)
    progressReporter.reportProgress(taskId: taskId, stage: .finalizing, percent: 95)

    guard
      let outputAttrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
      let outputSize = outputAttrs[.size] as? Int64,
      outputSize > 0
    else {
      throw PixelCompressorError.encodingError("Output file is empty or missing")
    }

    let durationMs = Int64(Date().timeIntervalSince(startTime) * 1000)
    let ratio = originalSize > 0 ? Double(outputSize) / Double(originalSize) : 0

    progressReporter.reportProgress(taskId: taskId, stage: .completed, percent: 100, force: true)

    return CompressionResultMessage(
      outputPath: outputURL.path,
      originalSizeBytes: originalSize,
      outputSizeBytes: outputSize,
      compressionRatio: ratio,
      durationMs: durationMs,
      codec: ImageFormatCodec.formatName(for: outputFormat),
      format: ImageFormatCodec.formatName(for: outputFormat)
    )
  }

  /// Decodes the source into a single upright `CGImage` with rotation
  /// baked in and (optionally) downscaled to fit `maxEdge` on its longest
  /// side.
  ///
  /// When downscaling is requested, uses `CGImageSourceCreateThumbnailAtIndex`
  /// with `kCGImageSourceCreateThumbnailWithTransform`, which bakes the
  /// source's own EXIF orientation automatically during the resize — so
  /// only the caller's own `requestedRotation` still needs applying on top,
  /// with a manual `CGContext` pass (applying `sourceOrientationDegrees`
  /// again here would double-rotate).
  ///
  /// When no downscaling is requested, the full-resolution image is
  /// decoded raw (no orientation baked by ImageIO) and the combined
  /// source+requested rotation is applied in one manual pass.
  private func decodeAndOrient(
    source: CGImageSource,
    sourceOrientationDegrees: Int,
    requestedRotation: Int,
    maxEdge: Int?
  ) throws -> CGImage {
    if let maxEdge = maxEdge {
      let options: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else {
        throw PixelCompressorError.decodingError("Could not decode/downscale source image")
      }
      if requestedRotation != 0 {
        return try ImageFormatCodec.rotate(thumbnail, byDegrees: requestedRotation)
      }
      return thumbnail
    }

    guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw PixelCompressorError.decodingError("Could not decode source image")
    }
    let totalRotation = RotationMath.combine(
      sourceDegrees: sourceOrientationDegrees, requestedDegrees: requestedRotation)
    if totalRotation != 0 {
      return try ImageFormatCodec.rotate(full, byDegrees: totalRotation)
    }
    return full
  }

  private func compressToTargetSize(
    taskId: String,
    baseImage: CGImage,
    format: ImageFormatWire,
    initialQuality: Int,
    targetSizeBytes: Int,
    properties: [CFString: Any]?,
    outputURL: URL
  ) throws {
    var quality = max(Constants.qualityFloor, min(initialQuality, 100))
    var image = baseImage

    var attempt = 0
    while attempt < Constants.maxAttempts {
      try checkCancelled(taskId)
      progressReporter.reportProgress(
        taskId: taskId, stage: .encoding, percent: 40 + Double(attempt) * 6,
        note: "attempt \(attempt + 1), quality \(quality), edge \(max(image.width, image.height))"
      )

      try ImageFormatCodec.encode(
        image: image, to: outputURL, format: format, quality: quality, properties: properties)

      let size =
        (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
      if size > 0 && size <= targetSizeBytes {
        return
      }

      attempt += 1
      if quality > Constants.qualityFloor {
        quality = max(Constants.qualityFloor, quality - Constants.qualityStep)
      } else {
        let currentEdge = max(image.width, image.height)
        let newEdge = max(
          Int(Double(currentEdge) * Constants.resolutionStepFactor), Constants.minEdgePx)
        if newEdge >= currentEdge {
          break
        }
        image = try ImageFormatCodec.resize(image, maxPixelSize: newEdge)
      }
    }

    throw PixelCompressorError.targetSizeUnachievable(
      "Could not reach target size of \(targetSizeBytes) bytes for image after \(Constants.maxAttempts) attempts"
    )
  }

  /// `ExifPolicy.keep`: copies the source's EXIF/TIFF/GPS property
  /// dictionaries as-is but forces orientation to 1 — pixels have already
  /// been rotated upright by `decodeAndOrient`, so a stale orientation tag
  /// would double-rotate the image in viewers that respect it.
  /// `ExifPolicy.strip`: writes no metadata at all.
  private func exifOutputProperties(
    policy: ExifPolicyWire, sourceProperties: [CFString: Any]
  ) -> [CFString: Any]? {
    switch policy {
    case .strip:
      return nil
    case .keep:
      var properties = sourceProperties
      properties[kCGImagePropertyOrientation] = 1
      return properties
    }
  }

  private func resolveOutputURL(request: ImageCompressRequest, format: ImageFormatWire) throws
    -> URL
  {
    if let outputPath = request.outputPath, !outputPath.isEmpty {
      return URL(fileURLWithPath: outputPath)
    }
    let fileName = "\(request.taskId).\(ImageFormatCodec.fileExtension(for: format))"
    let path = try cacheManager.resolveOutputPath(kind: .images, fileName: fileName)
    return URL(fileURLWithPath: path)
  }

  private func checkCancelled(_ taskId: String) throws {
    if taskRegistry.isCancelled(taskId: taskId) {
      throw PixelCompressorError.cancelled()
    }
  }
}
