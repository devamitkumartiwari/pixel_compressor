package com.therivanta.pixelcompressor.image

import android.content.Context
import com.therivanta.pixelcompressor.CompressionResultMessage
import com.therivanta.pixelcompressor.CompressionStageWire
import com.therivanta.pixelcompressor.ExifPolicyWire
import com.therivanta.pixelcompressor.ImageCompressRequest
import com.therivanta.pixelcompressor.ImageFormatWire
import com.therivanta.pixelcompressor.cache.CacheKind
import com.therivanta.pixelcompressor.cache.CacheManager
import com.therivanta.pixelcompressor.capability.CapabilityProbe
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import com.therivanta.pixelcompressor.progress.ProgressReporter
import com.therivanta.pixelcompressor.util.RotationMath
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** Image compression pipeline: decode (EXIF-orientation-aware, downsampled)
 * -> rotate -> resize -> encode (JPEG/PNG/WEBP via `Bitmap.compress`, HEIC
 * via [HeicWriterSupport]) -> EXIF keep/strip -> optional target-size
 * iterative search.
 */
class ImageEngine(
  private val context: Context,
  private val cacheManager: CacheManager,
  private val capabilityProbe: CapabilityProbe,
  private val progressReporter: ProgressReporter,
) {

  private companion object {
    const val MAX_ATTEMPTS = 8
    const val QUALITY_STEP = 15
    const val QUALITY_FLOOR = 10
    const val RESOLUTION_STEP_FACTOR = 0.75
    const val MIN_EDGE_PX = 200
    const val INITIAL_TARGET_QUALITY = 90
  }

  suspend fun compress(request: ImageCompressRequest): CompressionResultMessage {
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

    // Format + codec-capability check happens before any decode work, per
    // the "never silently substitute a codec" contract.
    val format = request.format ?: ImageFormatCodec.detectFromPath(request.sourcePath)
    if (format == ImageFormatWire.HEIC && !capabilityProbe.isHevcSupported()) {
      throw PixelCompressorErrors.unsupportedCodec(
        "HEIC encode requires a hardware HEVC encoder, which this device does not report support for",
      )
    }

    currentCoroutineContext().ensureActive()
    progressReporter.onProgress(taskId, CompressionStageWire.ANALYZING, 5.0)

    try {
      BitmapTransform.decodeBounds(request.sourcePath)
    } catch (e: Exception) {
      throw PixelCompressorErrors.unsupportedMedia(
        "Source is not a decodable image: ${request.sourcePath}",
        e.toString(),
      )
    }

    val sourceOrientationDegrees = if (request.autoCorrectOrientation) {
      ExifSupport.readOrientationDegrees(request.sourcePath)
    } else {
      0
    }
    val totalRotation = RotationMath.combineRotation(sourceOrientationDegrees, request.rotationDegrees.toInt())
    val requestedMaxWidth = request.maxWidth?.toInt()
    val requestedMaxHeight = request.maxHeight?.toInt()

    progressReporter.onProgress(taskId, CompressionStageWire.DECODING, 10.0)

    val scratchDir = File(context.cacheDir, "pixel_compressor/tmp").apply { mkdirs() }

    val quality: Int
    val encodedBytes: ByteArray

    if (request.targetSizeBytes == null) {
      val bitmap = decodeRotateFit(request.sourcePath, totalRotation, requestedMaxWidth, requestedMaxHeight)
      currentCoroutineContext().ensureActive()
      progressReporter.onProgress(taskId, CompressionStageWire.ENCODING, 50.0)
      quality = request.quality.toInt().coerceIn(1, 100)
      encodedBytes = try {
        ImageFormatCodec.encode(bitmap, format, quality, scratchDir)
      } finally {
        bitmap.recycle()
      }
    } else {
      val result = compressToTargetSize(
        taskId = taskId,
        sourcePath = request.sourcePath,
        totalRotation = totalRotation,
        requestedMaxWidth = requestedMaxWidth,
        requestedMaxHeight = requestedMaxHeight,
        format = format,
        targetSizeBytes = request.targetSizeBytes,
        scratchDir = scratchDir,
      )
      quality = result.quality
      encodedBytes = result.bytes
    }

    currentCoroutineContext().ensureActive()
    progressReporter.onProgress(taskId, CompressionStageWire.FINALIZING, 95.0)

    val outputPath = request.outputPath
      ?: cacheManager.resolveOutputPath(CacheKind.IMAGES, ImageFormatCodec.extensionFor(format))
    val outputFile = File(outputPath)
    outputFile.parentFile?.mkdirs()
    try {
      outputFile.writeBytes(encodedBytes)
    } catch (e: IOException) {
      throw mapWriteError(e)
    }

    if (request.exifPolicy == ExifPolicyWire.KEEP) {
      ExifSupport.copyExif(request.sourcePath, outputPath)
    }

    val outputSizeBytes = outputFile.length()
    val durationMs = System.currentTimeMillis() - startTime
    val ratio = if (originalSizeBytes > 0) outputSizeBytes.toDouble() / originalSizeBytes else 0.0

    progressReporter.onProgress(taskId, CompressionStageWire.COMPLETED, 100.0)

    return CompressionResultMessage(
      outputPath = outputPath,
      originalSizeBytes = originalSizeBytes,
      outputSizeBytes = outputSizeBytes,
      compressionRatio = ratio,
      durationMs = durationMs,
      codec = ImageFormatCodec.wireNameFor(format),
      format = ImageFormatCodec.wireNameFor(format),
    )
  }

  private fun decodeRotateFit(
    path: String,
    totalRotation: Int,
    maxWidth: Int?,
    maxHeight: Int?,
  ): android.graphics.Bitmap {
    // Generous pre-rotation sample target: rotation may swap width/height,
    // so sample against the larger of the two requested bounds with margin,
    // then fit exactly post-rotation.
    val sampleEdge = if (maxWidth != null || maxHeight != null) {
      max(maxWidth ?: 0, maxHeight ?: 0) * 2
    } else {
      null
    }
    var bitmap = BitmapTransform.decodeSampledBitmap(path, sampleEdge)
    bitmap = BitmapTransform.rotate(bitmap, totalRotation)
    bitmap = BitmapTransform.fitToBox(bitmap, maxWidth, maxHeight)
    return bitmap
  }

  private data class TargetSizeAttemptResult(
    val bytes: ByteArray,
    val quality: Int,
  )

  private suspend fun compressToTargetSize(
    taskId: String,
    sourcePath: String,
    totalRotation: Int,
    requestedMaxWidth: Int?,
    requestedMaxHeight: Int?,
    format: ImageFormatWire,
    targetSizeBytes: Long,
    scratchDir: File,
  ): TargetSizeAttemptResult {
    var quality = INITIAL_TARGET_QUALITY
    var currentMaxWidth = requestedMaxWidth
    var currentMaxHeight = requestedMaxHeight
    var lastBytes: ByteArray? = null
    var attempt = 0

    while (attempt < MAX_ATTEMPTS) {
      attempt++
      currentCoroutineContext().ensureActive()

      val bitmap = decodeRotateFit(sourcePath, totalRotation, currentMaxWidth, currentMaxHeight)
      val width = bitmap.width
      val height = bitmap.height
      val attemptBytes = try {
        ImageFormatCodec.encode(bitmap, format, quality, scratchDir)
      } finally {
        bitmap.recycle()
      }
      lastBytes = attemptBytes

      val percent = 10.0 + (attempt.toDouble() / MAX_ATTEMPTS) * 80.0
      progressReporter.onProgress(
        taskId,
        CompressionStageWire.ENCODING,
        percent,
        note = "attempt $attempt/$MAX_ATTEMPTS quality=$quality edge=${max(width, height)}",
      )

      if (attemptBytes.size <= targetSizeBytes) {
        return TargetSizeAttemptResult(attemptBytes, quality)
      }

      if (attempt >= MAX_ATTEMPTS) break

      if (quality > QUALITY_FLOOR) {
        quality = max(QUALITY_FLOOR, quality - QUALITY_STEP)
      } else {
        val currentEdge = max(width, height)
        val newEdge = max(MIN_EDGE_PX, (currentEdge * RESOLUTION_STEP_FACTOR).toInt())
        currentMaxWidth = newEdge
        currentMaxHeight = newEdge
      }
    }

    throw PixelCompressorErrors.targetSizeUnachievable(
      "Could not reach target size of $targetSizeBytes bytes after $MAX_ATTEMPTS attempts " +
        "(best attempt: ${lastBytes?.size ?: 0} bytes)",
    )
  }

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
