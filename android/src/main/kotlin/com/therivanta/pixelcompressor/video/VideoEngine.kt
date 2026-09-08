package com.therivanta.pixelcompressor.video

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import com.therivanta.pixelcompressor.CompressionModeWire
import com.therivanta.pixelcompressor.CompressionResultMessage
import com.therivanta.pixelcompressor.CompressionStageWire
import com.therivanta.pixelcompressor.QualityPresetWire
import com.therivanta.pixelcompressor.VideoCompressRequest
import com.therivanta.pixelcompressor.cache.CacheKind
import com.therivanta.pixelcompressor.cache.CacheManager
import com.therivanta.pixelcompressor.capability.CapabilityProbe
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import com.therivanta.pixelcompressor.progress.ProgressReporter
import com.therivanta.pixelcompressor.util.RotationMath
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import kotlin.math.max
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Video compression pipeline. Orchestrates [VideoTranscoder] (video track)
 * and [AudioTranscoder] (audio track) then muxes their buffered output
 * into a single MP4 via [MediaMuxer]. Smart mode derives
 * resolution/fps/bitrate from a [QualityPresetWire] ([VideoBitrateMath]);
 * manual mode uses request values, falling back to source values
 * (resolution/fps) or medium-preset-derived values (bitrate/audio
 * bitrate) for anything unset. An explicit `targetSizeBytes` runs a
 * bounded re-encode loop, stepping bitrate down to a floor and then
 * resolution down, per [VideoBitrateMath.nextAttempt].
 */
class VideoEngine(
  private val context: Context,
  private val cacheManager: CacheManager,
  private val capabilityProbe: CapabilityProbe,
  private val progressReporter: ProgressReporter,
) {

  suspend fun compress(request: VideoCompressRequest): CompressionResultMessage {
    val startTime = System.currentTimeMillis()
    val taskId = request.taskId
    progressReporter.onProgress(taskId, CompressionStageWire.PREPARING, 0.0)

    val sourceFile = File(request.sourcePath)
    if (!sourceFile.exists()) {
      throw PixelCompressorErrors.invalidMedia("Source file does not exist: ${request.sourcePath}")
    }
    if (!sourceFile.canRead()) {
      throw PixelCompressorErrors.permissionDenied("Cannot read source file: ${request.sourcePath}")
    }
    val originalSizeBytes = sourceFile.length()

    currentCoroutineContext().ensureActive()
    progressReporter.onProgress(taskId, CompressionStageWire.ANALYZING, 5.0)

    var videoTrackIndex = -1
    var probedVideoFormat: MediaFormat? = null
    var audioTrackIndex = -1
    var probedAudioFormat: MediaFormat? = null

    val probeExtractor = MediaExtractor()
    try {
      try {
        probeExtractor.setDataSource(request.sourcePath)
      } catch (e: Exception) {
        throw PixelCompressorErrors.unsupportedMedia(
          "Source is not a decodable video: ${request.sourcePath}",
          e.toString(),
        )
      }
      for (i in 0 until probeExtractor.trackCount) {
        val format = probeExtractor.getTrackFormat(i)
        val mime = if (format.containsKey(MediaFormat.KEY_MIME)) format.getString(MediaFormat.KEY_MIME) else null
        when {
          mime?.startsWith("video/") == true && videoTrackIndex == -1 -> {
            videoTrackIndex = i
            probedVideoFormat = format
          }
          mime?.startsWith("audio/") == true && audioTrackIndex == -1 -> {
            audioTrackIndex = i
            probedAudioFormat = format
          }
        }
      }
    } finally {
      probeExtractor.release()
    }

    if (videoTrackIndex == -1) {
      throw PixelCompressorErrors.unsupportedMedia("No decodable video track found in ${request.sourcePath}")
    }
    val videoFormat = probedVideoFormat
      ?: throw PixelCompressorErrors.unsupportedMedia("No decodable video track found in ${request.sourcePath}")
    val audioFormat = probedAudioFormat
    val hasAudioTrack = audioTrackIndex != -1 && audioFormat != null
    val useAudio = request.audioEnabled && hasAudioTrack

    val sourceWidth = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
    val sourceHeight = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
    val sourceFps = try {
      if (videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE) else 30
    } catch (_: Exception) {
      30
    }

    val retriever = MediaMetadataRetriever()
    var sourceRotationDegrees = 0
    var sourceDurationMs = 0L
    try {
      retriever.setDataSource(request.sourcePath)
      sourceRotationDegrees =
        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
      sourceDurationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
    } catch (_: Exception) {
      // Non-fatal: rotation defaults to 0, duration falls back to the
      // track format's KEY_DURATION below.
    } finally {
      retriever.release()
    }
    if (sourceDurationMs <= 0 && videoFormat.containsKey(MediaFormat.KEY_DURATION)) {
      sourceDurationMs = videoFormat.getLong(MediaFormat.KEY_DURATION) / 1000
    }

    val totalRotation = RotationMath.combineRotation(sourceRotationDegrees, request.rotationDegrees.toInt())
    val resolvedCodec = VideoCodecSelection.resolve(request.codec, capabilityProbe)

    currentCoroutineContext().ensureActive()

    val trimStartUs = (request.trimStartMs?.coerceAtLeast(0) ?: 0L) * 1000L
    val trimEndUs = request.trimEndMs?.let { it * 1000L }
    val effectiveDurationUs = (trimEndUs ?: (sourceDurationMs * 1000L)) - trimStartUs
    val progressDurationUs = if (effectiveDurationUs > 0) effectiveDurationUs else 1L

    val preset = request.preset ?: QualityPresetWire.MEDIUM
    val baseDims: VideoBitrateMath.Dimensions
    val fps: Int
    val videoBitrateBps: Long
    val audioBitrateBps: Long

    if (request.mode == CompressionModeWire.SMART) {
      val presetDims = VideoBitrateMath.deriveResolution(preset, sourceWidth, sourceHeight)
      baseDims = VideoBitrateMath.capToBox(
        presetDims.width,
        presetDims.height,
        request.maxWidth?.toInt(),
        request.maxHeight?.toInt(),
      )
      fps = request.fps?.toInt() ?: VideoBitrateMath.deriveFps(preset, sourceFps)
      videoBitrateBps = VideoBitrateMath.deriveBitrateBps(preset, baseDims.width, baseDims.height, fps, resolvedCodec.isHevc)
      audioBitrateBps = VideoBitrateMath.deriveAudioBitrateBps(preset)
    } else {
      baseDims = VideoBitrateMath.capToBox(sourceWidth, sourceHeight, request.maxWidth?.toInt(), request.maxHeight?.toInt())
      fps = request.fps?.toInt() ?: sourceFps
      videoBitrateBps = request.bitrateBps
        ?: VideoBitrateMath.deriveBitrateBps(QualityPresetWire.MEDIUM, baseDims.width, baseDims.height, fps, resolvedCodec.isHevc)
      audioBitrateBps = request.audioBitrateBps ?: VideoBitrateMath.deriveAudioBitrateBps(QualityPresetWire.MEDIUM)
    }

    val scratchDir = File(context.cacheDir, "pixel_compressor/tmp").apply { mkdirs() }
    val finalOutputPath = request.outputPath ?: cacheManager.resolveOutputPath(CacheKind.VIDEOS, "mp4")
    val sourceLongEdge = max(sourceWidth, sourceHeight)

    progressReporter.onProgress(taskId, CompressionStageWire.DECODING, 10.0)

    val resultFile: File

    val encodedBaseDims = swapForRotation(baseDims.width, baseDims.height, totalRotation)

    if (request.targetSizeBytes == null) {
      val scratch = File.createTempFile("pc_video_attempt", ".mp4", scratchDir)
      runAttempt(
        taskId = taskId,
        sourcePath = request.sourcePath,
        videoTrackIndex = videoTrackIndex,
        videoFormat = videoFormat,
        outputMime = resolvedCodec.mime,
        width = encodedBaseDims.first,
        height = encodedBaseDims.second,
        fps = fps,
        videoBitrateBps = videoBitrateBps,
        useAudio = useAudio,
        audioTrackIndex = audioTrackIndex,
        audioFormat = audioFormat,
        audioBitrateBps = audioBitrateBps,
        trimStartUs = trimStartUs,
        trimEndUs = trimEndUs,
        rotationDegrees = totalRotation,
        outputFile = scratch,
        progressStart = 10.0,
        progressEnd = 90.0,
        progressDurationUs = progressDurationUs,
        attemptNote = null,
      )
      resultFile = scratch
    } else {
      val maxAttempts = VideoBitrateMath.TARGET_SIZE_MAX_ATTEMPTS
      var state = VideoBitrateMath.AttemptState(
        bitrateBps = VideoBitrateMath.estimateStartingBitrateBps(
          request.targetSizeBytes,
          effectiveDurationUs / 1000,
          useAudio,
        ),
        maxEdgePx = null,
      )
      var attempt = 0
      var success: File? = null
      var lastSize = 0L
      var lastBitrate = state.bitrateBps
      while (attempt < maxAttempts) {
        attempt++
        currentCoroutineContext().ensureActive()
        val dims = state.maxEdgePx?.let { VideoBitrateMath.fitLongestEdge(baseDims.width, baseDims.height, it) }
          ?: baseDims
        val encodedDims = swapForRotation(dims.width, dims.height, totalRotation)
        val scratch = File.createTempFile("pc_video_attempt${attempt}_", ".mp4", scratchDir)
        val rangeStart = 10.0 + (attempt - 1).toDouble() / maxAttempts * 80.0
        val rangeEnd = 10.0 + attempt.toDouble() / maxAttempts * 80.0
        runAttempt(
          taskId = taskId,
          sourcePath = request.sourcePath,
          videoTrackIndex = videoTrackIndex,
          videoFormat = videoFormat,
          outputMime = resolvedCodec.mime,
          width = encodedDims.first,
          height = encodedDims.second,
          fps = fps,
          videoBitrateBps = state.bitrateBps,
          useAudio = useAudio,
          audioTrackIndex = audioTrackIndex,
          audioFormat = audioFormat,
          audioBitrateBps = audioBitrateBps,
          trimStartUs = trimStartUs,
          trimEndUs = trimEndUs,
          rotationDegrees = totalRotation,
          outputFile = scratch,
          progressStart = rangeStart,
          progressEnd = rangeEnd,
          progressDurationUs = progressDurationUs,
          attemptNote = "attempt $attempt/$maxAttempts bitrate=${state.bitrateBps} edge=${max(dims.width, dims.height)}",
        )
        lastSize = scratch.length()
        lastBitrate = state.bitrateBps
        if (lastSize <= request.targetSizeBytes) {
          success = scratch
          break
        }
        scratch.delete()
        if (attempt >= maxAttempts) break
        state = VideoBitrateMath.nextAttempt(state, sourceLongEdge)
      }
      resultFile = success ?: throw PixelCompressorErrors.targetSizeUnachievable(
        "Could not reach target size of ${request.targetSizeBytes} bytes after $maxAttempts attempts " +
          "(last size: $lastSize bytes, last bitrate: $lastBitrate bps)",
      )
    }

    currentCoroutineContext().ensureActive()
    progressReporter.onProgress(taskId, CompressionStageWire.FINALIZING, 95.0)

    val outputFile = File(finalOutputPath)
    outputFile.parentFile?.mkdirs()
    try {
      resultFile.copyTo(outputFile, overwrite = true)
    } catch (e: IOException) {
      throw mapWriteError(e)
    } finally {
      resultFile.delete()
    }

    val outputSizeBytes = outputFile.length()
    val durationMs = System.currentTimeMillis() - startTime
    val ratio = if (originalSizeBytes > 0) outputSizeBytes.toDouble() / originalSizeBytes else 0.0

    progressReporter.onProgress(taskId, CompressionStageWire.COMPLETED, 100.0)

    return CompressionResultMessage(
      outputPath = finalOutputPath,
      originalSizeBytes = originalSizeBytes,
      outputSizeBytes = outputSizeBytes,
      compressionRatio = ratio,
      durationMs = durationMs,
      codec = resolvedCodec.wireName,
      format = "mp4",
    )
  }

  @Suppress("LongParameterList")
  private suspend fun runAttempt(
    taskId: String,
    sourcePath: String,
    videoTrackIndex: Int,
    videoFormat: MediaFormat,
    outputMime: String,
    width: Int,
    height: Int,
    fps: Int,
    videoBitrateBps: Long,
    useAudio: Boolean,
    audioTrackIndex: Int,
    audioFormat: MediaFormat?,
    audioBitrateBps: Long,
    trimStartUs: Long,
    trimEndUs: Long?,
    rotationDegrees: Int,
    outputFile: File,
    progressStart: Double,
    progressEnd: Double,
    progressDurationUs: Long,
    attemptNote: String?,
  ) {
    val videoResult = VideoTranscoder().transcode(
      sourcePath = sourcePath,
      videoTrackIndex = videoTrackIndex,
      sourceFormat = videoFormat,
      outputMime = outputMime,
      targetWidth = width,
      targetHeight = height,
      targetFps = fps,
      bitrateBps = videoBitrateBps,
      trimStartUs = trimStartUs,
      trimEndUs = trimEndUs,
      rotationDegrees = rotationDegrees,
    ) { pts ->
      val relativePts = (pts - trimStartUs).coerceAtLeast(0)
      val fraction = (relativePts.toDouble() / progressDurationUs).coerceIn(0.0, 1.0)
      val percent = progressStart + fraction * (progressEnd - progressStart)
      progressReporter.onProgress(taskId, CompressionStageWire.ENCODING, percent, note = attemptNote)
    }

    val audioResult = if (useAudio && audioTrackIndex != -1 && audioFormat != null) {
      AudioTranscoder().transcode(sourcePath, audioTrackIndex, audioFormat, audioBitrateBps, trimStartUs, trimEndUs)
    } else {
      null
    }

    currentCoroutineContext().ensureActive()
    progressReporter.onProgress(taskId, CompressionStageWire.MUXING, progressEnd, note = attemptNote)
    muxToFile(videoResult, audioResult, outputFile)
  }

  private fun muxToFile(
    videoResult: VideoTranscoder.Result,
    audioResult: AudioTranscoder.Result?,
    outputFile: File,
  ) {
    val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    try {
      val videoTrackIdx = muxer.addTrack(videoResult.format)
      val audioTrackIdx = audioResult?.let { muxer.addTrack(it.format) }
      // Rotation is now baked directly into the encoded pixels (see
      // VideoTranscoder/GlUtil), so no orientation hint is needed — a
      // player/transcoder that ignores this metadata already renders the
      // frame correctly.
      muxer.start()

      val videoSamples = videoResult.samples
      val audioSamples = audioResult?.samples ?: emptyList()
      var vi = 0
      var ai = 0
      while (vi < videoSamples.size || ai < audioSamples.size) {
        val writeVideo = when {
          vi >= videoSamples.size -> false
          ai >= audioSamples.size -> true
          else -> videoSamples[vi].presentationTimeUs <= audioSamples[ai].presentationTimeUs
        }
        if (writeVideo) {
          writeSample(muxer, videoTrackIdx, videoSamples[vi])
          vi++
        } else {
          writeSample(muxer, audioTrackIdx!!, audioSamples[ai])
          ai++
        }
      }

      muxer.stop()
    } catch (e: Exception) {
      throw PixelCompressorErrors.encodingError("Muxing failed: ${e.message}", e.toString())
    } finally {
      muxer.release()
    }
  }

  private fun writeSample(muxer: MediaMuxer, trackIndex: Int, sample: EncodedSample) {
    val buffer = ByteBuffer.wrap(sample.data)
    val info = MediaCodec.BufferInfo().apply {
      set(0, sample.data.size, sample.presentationTimeUs, sample.flags)
    }
    muxer.writeSampleData(trackIndex, buffer, info)
  }

  /**
   * Rotation is baked into the encoded pixels (see [VideoTranscoder]), so
   * for a 90/270 bake the encoder's target frame is portrait/landscape-swapped
   * relative to [width]/[height], which are expressed in the source's raw
   * (pre-rotation) orientation.
   */
  private fun swapForRotation(width: Int, height: Int, rotationDegrees: Int): Pair<Int, Int> =
    if (rotationDegrees == 90 || rotationDegrees == 270) height to width else width to height

  private fun mapWriteError(e: IOException): Throwable {
    val message = e.message ?: ""
    return if (message.contains("ENOSPC", ignoreCase = true) ||
      message.contains("No space left", ignoreCase = true)
    ) {
      PixelCompressorErrors.insufficientStorage("No space left to write output file", e.toString())
    } else {
      PixelCompressorErrors.encodingError("Failed to write output file: ${e.message}", e.toString())
    }
  }
}
