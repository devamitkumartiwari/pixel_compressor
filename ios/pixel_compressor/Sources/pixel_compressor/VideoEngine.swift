import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Implements `VideoHostApi.compressVideo`.
///
/// - `CompressionMode.smart` (no `targetSizeBytes`): `AVAssetExportSession`
///   with a quality-tier preset (`AVCodecKey` chosen via
///   `VideoCodecSelection.resolveCodecType`), `timeRange` for trim, and an
///   `AVMutableVideoComposition` for resolution/rotation control.
/// - `CompressionMode.manual` (no `targetSizeBytes`), and *every*
///   `targetSizeBytes` request regardless of mode: `AVAssetReader` +
///   `AVAssetWriter` with an explicit `AVVideoAverageBitRateKey`, since
///   export-session presets don't accept an arbitrary numeric bitrate and
///   the target-size loop needs exact bitrate control across attempts.
final class VideoEngine {
  private let cacheManager: CacheManager
  private let taskRegistry: TaskRegistry
  private let progressReporter: ProgressReporter

  private enum Constants {
    static let maxAttempts = 5
    static let bitrateStepFactor = 0.65
    static let minBitrateBps = 300_000
    static let resolutionStepFactor = 0.75
    static let minEdgePx = 320
  }

  init(cacheManager: CacheManager, taskRegistry: TaskRegistry, progressReporter: ProgressReporter) {
    self.cacheManager = cacheManager
    self.taskRegistry = taskRegistry
    self.progressReporter = progressReporter
  }

  func compress(request: VideoCompressRequest) throws -> CompressionResultMessage {
    let taskId = request.taskId
    let startTime = Date()

    try checkCancelled(taskId)
    progressReporter.reportProgress(taskId: taskId, stage: .preparing, percent: 0)

    guard FileManager.default.fileExists(atPath: request.sourcePath) else {
      throw PixelCompressorError.invalidMedia("Source file does not exist: \(request.sourcePath)")
    }
    let sourceURL = URL(fileURLWithPath: request.sourcePath)
    let asset = AVURLAsset(url: sourceURL)

    guard let videoTrack = firstTrack(of: .video, in: asset) else {
      throw PixelCompressorError.unsupportedMedia("No video track found in source")
    }
    let audioTrack = request.audioEnabled ? firstTrack(of: .audio, in: asset) : nil

    progressReporter.reportProgress(taskId: taskId, stage: .analyzing, percent: 5)

    let durationSeconds = asset.duration.seconds
    guard durationSeconds.isFinite, durationSeconds > 0 else {
      throw PixelCompressorError.invalidMedia("Source video has no readable duration")
    }
    var trimStart = 0.0
    var trimEnd = durationSeconds
    if let startMs = request.trimStartMs {
      trimStart = max(0, Double(startMs) / 1000.0)
    }
    if let endMs = request.trimEndMs {
      trimEnd = min(durationSeconds, Double(endMs) / 1000.0)
    }
    guard trimEnd > trimStart else {
      throw PixelCompressorError.invalidMedia("trimEndMs must be after trimStartMs")
    }

    let requestedRotation = try RotationMath.requireCardinal(Int(request.rotationDegrees))
    let (displayWidth, displayHeight) = displaySize(
      track: videoTrack, extraDegrees: requestedRotation)
    let sourceFps = videoTrack.nominalFrameRate > 0 ? Double(videoTrack.nominalFrameRate) : 30.0

    let hevcSupported = CapabilityProbe.probeHevcEncoder()
    let (codecType, isHevc) = try VideoCodecSelection.resolveCodecType(
      requested: request.codec, hevcSupported: hevcSupported)

    let preset = request.preset ?? .medium
    let smartSettings = VideoCodecSelection.smartSettings(
      preset: preset,
      sourceWidth: displayWidth,
      sourceHeight: displayHeight,
      sourceFps: sourceFps,
      requestedMaxWidth: request.maxWidth.map { Int($0) },
      requestedMaxHeight: request.maxHeight.map { Int($0) },
      requestedFps: request.fps.map { Int($0) },
      isHevc: isHevc
    )
    let manualSettings = VideoCodecSelection.manualSettings(
      sourceWidth: displayWidth,
      sourceHeight: displayHeight,
      sourceFps: sourceFps,
      requestedMaxWidth: request.maxWidth.map { Int($0) },
      requestedMaxHeight: request.maxHeight.map { Int($0) },
      requestedFps: request.fps.map { Int($0) },
      requestedBitrateBps: request.bitrateBps.map { Int($0) },
      requestedAudioBitrateBps: request.audioBitrateBps.map { Int($0) },
      isHevc: isHevc
    )

    let outputURL = try resolveOutputURL(request: request)
    try? FileManager.default.removeItem(at: outputURL)
    let originalSize =
      (try? FileManager.default.attributesOfItem(atPath: request.sourcePath)[.size] as? Int64) ?? 0

    try checkCancelled(taskId)

    if let targetSizeBytes = request.targetSizeBytes {
      try compressWithTargetSize(
        taskId: taskId,
        asset: asset,
        videoTrack: videoTrack,
        audioTrack: audioTrack,
        trimStart: trimStart,
        trimEnd: trimEnd,
        requestedRotation: requestedRotation,
        codecType: codecType,
        initialSettings: manualSettings,
        audioEnabled: request.audioEnabled,
        targetSizeBytes: Int64(targetSizeBytes),
        outputURL: outputURL
      )
    } else if request.mode == .smart {
      try runSmartExport(
        taskId: taskId,
        asset: asset,
        videoTrack: videoTrack,
        trimStart: trimStart,
        trimEnd: trimEnd,
        requestedRotation: requestedRotation,
        settings: smartSettings,
        isHevc: isHevc,
        audioEnabled: request.audioEnabled,
        outputURL: outputURL
      )
    } else {
      try runManualEncode(
        taskId: taskId,
        asset: asset,
        videoTrack: videoTrack,
        audioTrack: audioTrack,
        trimStart: trimStart,
        trimEnd: trimEnd,
        requestedRotation: requestedRotation,
        codecType: codecType,
        width: manualSettings.width,
        height: manualSettings.height,
        fps: manualSettings.fps,
        bitrateBps: manualSettings.bitrateBps,
        audioEnabled: request.audioEnabled,
        audioBitrateBps: manualSettings.audioBitrateBps,
        outputURL: outputURL
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
      codec: isHevc ? "hevc" : "h264",
      format: "mp4"
    )
  }

  // MARK: - Smart mode (AVAssetExportSession)

  private func runSmartExport(
    taskId: String,
    asset: AVURLAsset,
    videoTrack: AVAssetTrack,
    trimStart: Double,
    trimEnd: Double,
    requestedRotation: Int,
    settings: VideoCodecSelection.DerivedSettings,
    isHevc: Bool,
    audioEnabled: Bool,
    outputURL: URL
  ) throws {
    let presetName =
      isHevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
    let resolvedPresetName =
      compatiblePresets.contains(presetName) ? presetName : AVAssetExportPresetHighestQuality

    let trimRange = CMTimeRange(
      start: CMTime(seconds: trimStart, preferredTimescale: 600),
      end: CMTime(seconds: trimEnd, preferredTimescale: 600)
    )

    // Build a trimmed, 0-based composition first (video always, audio only
    // if enabled) so the video-composition instruction below has a single
    // unambiguous timeline to work with, regardless of trim — avoids
    // subtle timeline-mismatch bugs from mixing `exportSession.timeRange`
    // (source-asset-relative) with a video composition (which would also
    // need to be source-asset-relative, easy to get wrong).
    let trimmedComposition = AVMutableComposition()
    guard
      let compVideoTrack = trimmedComposition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw PixelCompressorError.encodingError("Could not build export composition")
    }
    try compVideoTrack.insertTimeRange(trimRange, of: videoTrack, at: .zero)

    if audioEnabled, let audioTrack = firstTrack(of: .audio, in: asset) {
      if
        let compAudioTrack = trimmedComposition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      {
        try? compAudioTrack.insertTimeRange(trimRange, of: audioTrack, at: .zero)
      }
    }

    guard
      let exportSession = AVAssetExportSession(
        asset: trimmedComposition, presetName: resolvedPresetName)
    else {
      throw PixelCompressorError.encodingError("Could not create export session")
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: settings.width, height: settings.height)
    composition.frameDuration = CMTime(value: 1, timescale: Int32(max(1, settings.fps)))
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: trimmedComposition.duration)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
    layerInstruction.setTransform(
      layerTransform(
        track: videoTrack, extraDegrees: requestedRotation, renderSize: composition.renderSize),
      at: .zero
    )
    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]
    exportSession.videoComposition = composition

    try runExport(exportSession, taskId: taskId)
  }

  private func runExport(_ exportSession: AVAssetExportSession, taskId: String) throws {
    let semaphore = DispatchSemaphore(value: 0)
    exportSession.exportAsynchronously {
      semaphore.signal()
    }
    while exportSession.status == .exporting || exportSession.status == .waiting {
      if taskRegistry.isCancelled(taskId: taskId) {
        exportSession.cancelExport()
        break
      }
      progressReporter.reportProgress(
        taskId: taskId, stage: .encoding, percent: Double(exportSession.progress) * 100)
      Thread.sleep(forTimeInterval: 0.1)
    }
    semaphore.wait()

    switch exportSession.status {
    case .completed:
      return
    case .cancelled:
      throw PixelCompressorError.cancelled()
    default:
      throw PixelCompressorError.encodingError(
        exportSession.error?.localizedDescription ?? "Video export failed")
    }
  }

  // MARK: - Manual mode / target-size loop (AVAssetReader + AVAssetWriter)

  private func compressWithTargetSize(
    taskId: String,
    asset: AVURLAsset,
    videoTrack: AVAssetTrack,
    audioTrack: AVAssetTrack?,
    trimStart: Double,
    trimEnd: Double,
    requestedRotation: Int,
    codecType: AVVideoCodecType,
    initialSettings: VideoCodecSelection.DerivedSettings,
    audioEnabled: Bool,
    targetSizeBytes: Int64,
    outputURL: URL
  ) throws {
    let durationSeconds = max(trimEnd - trimStart, 0.001)
    let audioReserveFraction = audioEnabled ? 0.08 : 0.0
    let safetyFactor = 0.9
    let targetBits = Double(targetSizeBytes) * 8.0 * safetyFactor
    let videoBits = targetBits * (1 - audioReserveFraction)
    var bitrateBps = max(Int(videoBits / durationSeconds), Constants.minBitrateBps)

    var width = initialSettings.width
    var height = initialSettings.height
    let fps = initialSettings.fps
    let audioBitrateBps = audioEnabled ? initialSettings.audioBitrateBps : 0

    var attempt = 0
    while attempt < Constants.maxAttempts {
      try checkCancelled(taskId)
      progressReporter.reportProgress(
        taskId: taskId, stage: .encoding, percent: 5,
        note: "attempt \(attempt + 1), bitrate \(bitrateBps), \(width)x\(height)"
      )

      try runManualEncode(
        taskId: taskId,
        asset: asset,
        videoTrack: videoTrack,
        audioTrack: audioTrack,
        trimStart: trimStart,
        trimEnd: trimEnd,
        requestedRotation: requestedRotation,
        codecType: codecType,
        width: width,
        height: height,
        fps: fps,
        bitrateBps: bitrateBps,
        audioEnabled: audioEnabled,
        audioBitrateBps: audioBitrateBps,
        outputURL: outputURL
      )

      let size =
        (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
      if size > 0 && size <= targetSizeBytes {
        return
      }

      attempt += 1
      if attempt >= Constants.maxAttempts { break }

      if bitrateBps > Constants.minBitrateBps {
        bitrateBps = max(
          Int(Double(bitrateBps) * Constants.bitrateStepFactor), Constants.minBitrateBps)
      } else {
        let currentEdge = max(width, height)
        let newEdge = max(
          Int(Double(currentEdge) * Constants.resolutionStepFactor), Constants.minEdgePx)
        if newEdge >= currentEdge {
          break
        }
        let (newWidth, newHeight) = VideoCodecSelection.scaledSize(
          sourceWidth: width, sourceHeight: height, targetLongestEdge: newEdge)
        width = newWidth
        height = newHeight
      }
    }

    throw PixelCompressorError.targetSizeUnachievable(
      "Could not reach target size of \(targetSizeBytes) bytes for video after \(Constants.maxAttempts) attempts"
    )
  }

  private func runManualEncode(
    taskId: String,
    asset: AVURLAsset,
    videoTrack: AVAssetTrack,
    audioTrack: AVAssetTrack?,
    trimStart: Double,
    trimEnd: Double,
    requestedRotation: Int,
    codecType: AVVideoCodecType,
    width: Int,
    height: Int,
    fps: Int,
    bitrateBps: Int,
    audioEnabled: Bool,
    audioBitrateBps: Int,
    outputURL: URL
  ) throws {
    try? FileManager.default.removeItem(at: outputURL)

    guard let reader = try? AVAssetReader(asset: asset) else {
      throw PixelCompressorError.decodingError("Could not create asset reader")
    }
    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
      throw PixelCompressorError.encodingError("Could not create asset writer")
    }

    let trimStartTime = CMTime(seconds: trimStart, preferredTimescale: 600)
    let trimEndTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
    let timeRange = CMTimeRange(start: trimStartTime, end: trimEndTime)
    reader.timeRange = timeRange

    // Decode through an AVAssetReaderVideoCompositionOutput so AVFoundation
    // performs the resize + source/requested rotation during decode,
    // handing us pixel buffers already at the final render size and
    // upright orientation — simpler and more robust than manually
    // resizing/rotating raw un-transformed sample buffers ourselves. Since
    // this composition is layered directly over the source `videoTrack`
    // (no intermediate AVComposition remap), its instruction timeline must
    // stay expressed in the *source asset's own* timeline, matching
    // `reader.timeRange` above — not a 0-based trimmed timeline.
    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: width, height: height)
    composition.frameDuration = CMTime(value: 1, timescale: Int32(max(1, fps)))
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = timeRange
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(
      layerTransform(
        track: videoTrack, extraDegrees: requestedRotation,
        renderSize: composition.renderSize), at: trimStartTime)
    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]

    let videoReaderOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: [videoTrack],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    videoReaderOutput.videoComposition = composition
    videoReaderOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(videoReaderOutput) else {
      throw PixelCompressorError.decodingError("Cannot read video track")
    }
    reader.add(videoReaderOutput)

    var audioReaderOutput: AVAssetReaderTrackOutput?
    if audioEnabled, let audioTrack = audioTrack {
      let output = AVAssetReaderTrackOutput(
        track: audioTrack,
        outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
      )
      output.alwaysCopiesSampleData = false
      if reader.canAdd(output) {
        reader.add(output)
        audioReaderOutput = output
      }
    }

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: codecType,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrateBps,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps,
      ],
    ]
    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoWriterInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoWriterInput) else {
      throw PixelCompressorError.encodingError("Cannot add video writer input")
    }
    writer.add(videoWriterInput)

    var audioWriterInput: AVAssetWriterInput?
    if audioEnabled, audioReaderOutput != nil {
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: audioBitrateBps,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100,
      ]
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        audioWriterInput = input
      }
    }

    guard reader.startReading() else {
      throw PixelCompressorError.decodingError(
        reader.error?.localizedDescription ?? "Failed to start reading source video")
    }
    guard writer.startWriting() else {
      throw PixelCompressorError.encodingError(
        writer.error?.localizedDescription ?? "Failed to start writing output video")
    }
    writer.startSession(atSourceTime: trimStartTime)

    var cancelled = false
    let durationSeconds = max(trimEnd - trimStart, 0.001)

    let videoQueue = DispatchQueue(label: "com.therivanta.pixel_compressor.video_encode")
    let videoDone = DispatchSemaphore(value: 0)
    videoWriterInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
      guard let self = self else {
        videoDone.signal()
        return
      }
      while videoWriterInput.isReadyForMoreMediaData {
        if self.taskRegistry.isCancelled(taskId: taskId) {
          cancelled = true
          videoWriterInput.markAsFinished()
          videoDone.signal()
          return
        }
        guard let sample = videoReaderOutput.copyNextSampleBuffer() else {
          videoWriterInput.markAsFinished()
          videoDone.signal()
          return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if pts.isValid {
          let elapsed = pts.seconds - trimStart
          let percent = min(max(elapsed / durationSeconds * 100, 0), 100)
          self.progressReporter.reportProgress(taskId: taskId, stage: .encoding, percent: percent)
        }
        if !videoWriterInput.append(sample) {
          videoWriterInput.markAsFinished()
          videoDone.signal()
          return
        }
      }
    }
    videoDone.wait()

    if !cancelled, let audioWriterInput = audioWriterInput, let audioReaderOutput = audioReaderOutput
    {
      let audioQueue = DispatchQueue(label: "com.therivanta.pixel_compressor.audio_encode")
      let audioDone = DispatchSemaphore(value: 0)
      audioWriterInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
        guard let self = self else {
          audioDone.signal()
          return
        }
        while audioWriterInput.isReadyForMoreMediaData {
          if cancelled || self.taskRegistry.isCancelled(taskId: taskId) {
            cancelled = true
            audioWriterInput.markAsFinished()
            audioDone.signal()
            return
          }
          guard let sample = audioReaderOutput.copyNextSampleBuffer() else {
            audioWriterInput.markAsFinished()
            audioDone.signal()
            return
          }
          if !audioWriterInput.append(sample) {
            audioWriterInput.markAsFinished()
            audioDone.signal()
            return
          }
        }
      }
      audioDone.wait()
    } else {
      audioWriterInput?.markAsFinished()
    }

    if cancelled {
      reader.cancelReading()
      let finishSemaphore = DispatchSemaphore(value: 0)
      writer.cancelWriting()
      finishSemaphore.signal()
      finishSemaphore.wait()
      try? FileManager.default.removeItem(at: outputURL)
      throw PixelCompressorError.cancelled()
    }

    let finishSemaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
      finishSemaphore.signal()
    }
    finishSemaphore.wait()

    guard writer.status == .completed else {
      throw PixelCompressorError.encodingError(
        writer.error?.localizedDescription ?? "Failed to finish writing output video")
    }
  }

  // MARK: - Rotation / geometry helpers

  /// The display-oriented `(width, height)` of `track` after both its own
  /// `preferredTransform` and an additional `extraDegrees` rotation are
  /// applied — this is what `maxWidth`/`maxHeight`/bitrate derivation
  /// should reason about, not the raw storage-orientation `naturalSize`.
  private func displaySize(track: AVAssetTrack, extraDegrees: Int) -> (width: Int, height: Int) {
    let rect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
    var width = Int(abs(rect.width).rounded())
    var height = Int(abs(rect.height).rounded())
    let normalized = RotationMath.normalize(extraDegrees)
    if normalized == 90 || normalized == 270 {
      swap(&width, &height)
    }
    return (max(2, width), max(2, height))
  }

  /// Combines the track's own `preferredTransform` (source rotation) with
  /// an additional `extraDegrees` rotation, then translates the result so
  /// its bounding box's origin lands at `(0, 0)` — the standard recipe for
  /// building a layer instruction transform that keeps rotated content
  /// fully inside `renderSize`.
  private func layerTransform(track: AVAssetTrack, extraDegrees: Int, renderSize: CGSize)
    -> CGAffineTransform
  {
    var transform = track.preferredTransform
    let normalized = RotationMath.normalize(extraDegrees)
    if normalized != 0 {
      let radians = CGFloat(normalized) * .pi / 180
      transform = transform.concatenating(CGAffineTransform(rotationAngle: radians))
    }
    let transformedRect = CGRect(origin: .zero, size: track.naturalSize).applying(transform)
    let translate = CGAffineTransform(
      translationX: -transformedRect.origin.x, y: -transformedRect.origin.y)
    transform = transform.concatenating(translate)

    // Scale into renderSize (which already reflects any resolution-derived
    // downscale) so the layer fills the composition frame exactly.
    let scaleX = transformedRect.width == 0 ? 1 : renderSize.width / abs(transformedRect.width)
    let scaleY = transformedRect.height == 0 ? 1 : renderSize.height / abs(transformedRect.height)
    transform = transform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
    return transform
  }

  // MARK: - Misc helpers

  private func firstTrack(of mediaType: AVMediaType, in asset: AVURLAsset) -> AVAssetTrack? {
    asset.tracks(withMediaType: mediaType).first
  }

  private func resolveOutputURL(request: VideoCompressRequest) throws -> URL {
    if let outputPath = request.outputPath, !outputPath.isEmpty {
      return URL(fileURLWithPath: outputPath)
    }
    let fileName = "\(request.taskId).mp4"
    let path = try cacheManager.resolveOutputPath(kind: .videos, fileName: fileName)
    return URL(fileURLWithPath: path)
  }

  private func checkCancelled(_ taskId: String) throws {
    if taskRegistry.isCancelled(taskId: taskId) {
      throw PixelCompressorError.cancelled()
    }
  }
}
