package com.therivanta.pixelcompressor.thumbnail

import android.content.Context
import android.media.MediaMetadataRetriever
import com.therivanta.pixelcompressor.CompressionStageWire
import com.therivanta.pixelcompressor.ThumbnailRequest
import com.therivanta.pixelcompressor.ThumbnailResultMessage
import com.therivanta.pixelcompressor.cache.CacheKind
import com.therivanta.pixelcompressor.cache.CacheManager
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import com.therivanta.pixelcompressor.image.BitmapTransform
import com.therivanta.pixelcompressor.image.ImageFormatCodec
import com.therivanta.pixelcompressor.progress.ProgressReporter
import java.io.File
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** Extracts frames from a video at requested timestamps via
 * [MediaMetadataRetriever.getFrameAtTime], reusing [BitmapTransform] for
 * resizing and [ImageFormatCodec] for encoding.
 */
class ThumbnailEngine(
  private val context: Context,
  private val cacheManager: CacheManager,
  private val progressReporter: ProgressReporter,
) {

  suspend fun generate(request: ThumbnailRequest): List<ThumbnailResultMessage> {
    val taskId = request.taskId
    val sourceFile = File(request.sourcePath)
    if (!sourceFile.exists()) {
      throw PixelCompressorErrors.invalidMedia("Source file does not exist: ${request.sourcePath}")
    }
    if (!sourceFile.canRead()) {
      throw PixelCompressorErrors.permissionDenied("Cannot read source file: ${request.sourcePath}")
    }

    progressReporter.onProgress(taskId, CompressionStageWire.PREPARING, 0.0)

    val retriever = MediaMetadataRetriever()
    try {
      try {
        retriever.setDataSource(request.sourcePath)
      } catch (e: Exception) {
        throw PixelCompressorErrors.unsupportedMedia(
          "Source is not a decodable video: ${request.sourcePath}",
          e.toString(),
        )
      }

      val scratchDir = File(context.cacheDir, "pixel_compressor/tmp").apply { mkdirs() }
      val total = request.positionsMs.size
      val results = mutableListOf<ThumbnailResultMessage>()
      val maxWidth = request.maxWidth.toInt()
      val maxHeight = request.maxHeight.toInt()
      val quality = request.quality.toInt().coerceIn(1, 100)

      for ((index, positionMs) in request.positionsMs.withIndex()) {
        currentCoroutineContext().ensureActive()

        val frame = try {
          retriever.getFrameAtTime(positionMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
        } catch (e: Exception) {
          throw PixelCompressorErrors.decodingError(
            "Failed to extract frame at ${positionMs}ms: ${e.message}",
            e.toString(),
          )
        } ?: throw PixelCompressorErrors.decodingError("No frame available at ${positionMs}ms")

        val fitted = BitmapTransform.fitToBox(frame, maxWidth, maxHeight)
        val width = fitted.width
        val height = fitted.height
        val bytes = try {
          ImageFormatCodec.encode(fitted, request.format, quality, scratchDir)
        } finally {
          fitted.recycle()
        }

        val outputPath = cacheManager.resolveOutputPath(
          CacheKind.THUMBNAILS,
          ImageFormatCodec.extensionFor(request.format),
        )
        File(outputPath).writeBytes(bytes)

        results.add(
          ThumbnailResultMessage(
            outputPath = outputPath,
            positionMs = positionMs,
            width = width.toLong(),
            height = height.toLong(),
          ),
        )

        val itemNumber = (index + 1)
        progressReporter.onProgress(
          taskId,
          CompressionStageWire.ENCODING,
          itemNumber.toDouble() / total * 100.0,
          currentItemIndex = itemNumber.toLong(),
          totalItems = total.toLong(),
        )
      }

      progressReporter.onProgress(taskId, CompressionStageWire.COMPLETED, 100.0)
      return results
    } finally {
      retriever.release()
    }
  }
}
