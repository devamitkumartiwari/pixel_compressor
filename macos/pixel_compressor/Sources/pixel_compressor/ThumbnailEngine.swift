import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// Implements `ThumbnailHostApi.generateThumbnails`: extracts an exact
/// frame per requested position with `AVAssetImageGenerator`, resizes via
/// the shared `ImageFormatCodec` helper (reused from the image pipeline),
/// and encodes each frame independently.
final class ThumbnailEngine {
  private let cacheManager: CacheManager
  private let taskRegistry: TaskRegistry
  private let progressReporter: ProgressReporter

  init(cacheManager: CacheManager, taskRegistry: TaskRegistry, progressReporter: ProgressReporter) {
    self.cacheManager = cacheManager
    self.taskRegistry = taskRegistry
    self.progressReporter = progressReporter
  }

  func generate(request: ThumbnailRequest) throws -> [ThumbnailResultMessage] {
    let taskId = request.taskId

    try checkCancelled(taskId)
    progressReporter.reportProgress(taskId: taskId, stage: .preparing, percent: 0)

    guard FileManager.default.fileExists(atPath: request.sourcePath) else {
      throw PixelCompressorError.invalidMedia("Source file does not exist: \(request.sourcePath)")
    }
    let sourceURL = URL(fileURLWithPath: request.sourcePath)
    let asset = AVURLAsset(url: sourceURL)

    guard !asset.tracks(withMediaType: .video).isEmpty else {
      throw PixelCompressorError.unsupportedMedia("No video track found in source")
    }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let format = request.format
    _ = try ImageFormatCodec.utType(for: format)  // reject WebP up front

    let maxEdge = max(Int(request.maxWidth), Int(request.maxHeight))
    let totalItems = request.positionsMs.count
    var results: [ThumbnailResultMessage] = []
    results.reserveCapacity(totalItems)

    for (index, positionMs) in request.positionsMs.enumerated() {
      try checkCancelled(taskId)

      let time = CMTime(value: positionMs, timescale: 1000)
      let cgImage: CGImage
      do {
        cgImage = try generator.copyCGImage(at: time, actualTime: nil)
      } catch {
        throw PixelCompressorError.decodingError(
          "Could not extract frame at \(positionMs)ms: \(error.localizedDescription)")
      }

      let resized = try ImageFormatCodec.resize(cgImage, maxPixelSize: maxEdge)

      let fileName = "\(taskId)_\(index).\(ImageFormatCodec.fileExtension(for: format))"
      let outputPath = try cacheManager.resolveOutputPath(kind: .thumbnails, fileName: fileName)
      let outputURL = URL(fileURLWithPath: outputPath)
      try? FileManager.default.removeItem(at: outputURL)

      try ImageFormatCodec.encode(
        image: resized, to: outputURL, format: format, quality: Int(request.quality))

      results.append(
        ThumbnailResultMessage(
          outputPath: outputURL.path,
          positionMs: positionMs,
          width: Int64(resized.width),
          height: Int64(resized.height)
        ))

      let percent = Double(index + 1) / Double(max(totalItems, 1)) * 100
      progressReporter.reportProgress(
        taskId: taskId, stage: .encoding, percent: percent,
        currentItemIndex: Int64(index + 1), totalItems: Int64(totalItems))
    }

    progressReporter.reportProgress(taskId: taskId, stage: .completed, percent: 100, force: true)
    return results
  }

  private func checkCancelled(_ taskId: String) throws {
    if taskRegistry.isCancelled(taskId: taskId) {
      throw PixelCompressorError.cancelled()
    }
  }
}
