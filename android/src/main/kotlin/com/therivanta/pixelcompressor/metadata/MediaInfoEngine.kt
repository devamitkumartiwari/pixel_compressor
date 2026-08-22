package com.therivanta.pixelcompressor.metadata

import android.graphics.BitmapFactory
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import com.therivanta.pixelcompressor.MediaInfoMessage
import com.therivanta.pixelcompressor.MediaInfoRequest
import com.therivanta.pixelcompressor.MediaTypeWire
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import com.therivanta.pixelcompressor.image.ExifSupport
import java.io.File

/** Reads media metadata: [BitmapFactory.Options]/[ExifSupport] for images,
 * [MediaMetadataRetriever] + [MediaExtractor] for video. Files that are
 * neither a decodable image nor video are reported as [MediaTypeWire.UNKNOWN]
 * (with just `sizeBytes` populated) rather than thrown as an error — the
 * request itself is well-formed, the content just isn't classifiable.
 */
class MediaInfoEngine {

  fun getMediaInfo(request: MediaInfoRequest): MediaInfoMessage {
    val file = File(request.sourcePath)
    if (!file.exists()) {
      throw PixelCompressorErrors.invalidMedia("Source file does not exist: ${request.sourcePath}")
    }
    if (!file.canRead()) {
      throw PixelCompressorErrors.permissionDenied("Cannot read source file: ${request.sourcePath}")
    }
    val sizeBytes = file.length()

    readImageInfo(request.sourcePath, sizeBytes)?.let { return it }
    readVideoInfo(request.sourcePath, sizeBytes)?.let { return it }

    return MediaInfoMessage(mediaType = MediaTypeWire.UNKNOWN, sizeBytes = sizeBytes)
  }

  private fun readImageInfo(path: String, sizeBytes: Long): MediaInfoMessage? {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    return try {
      BitmapFactory.decodeFile(path, options)
      if (options.outWidth <= 0 || options.outHeight <= 0) return null

      val exifPresent = ExifSupport.hasExif(path)
      val orientationDegrees = ExifSupport.readOrientationDegrees(path)
      val format = options.outMimeType?.substringAfter('/') ?: File(path).extension.lowercase()

      MediaInfoMessage(
        mediaType = MediaTypeWire.IMAGE,
        width = options.outWidth.toLong(),
        height = options.outHeight.toLong(),
        format = format,
        sizeBytes = sizeBytes,
        exifPresent = exifPresent,
        orientation = orientationDegrees.toLong(),
      )
    } catch (_: Exception) {
      null
    }
  }

  private fun readVideoInfo(path: String, sizeBytes: Long): MediaInfoMessage? {
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(path)

      val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
      val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
      val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
      val width = widthStr?.toLongOrNull()
      val height = heightStr?.toLongOrNull()
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null
      }

      val bitrateBps = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
      val hasAudioMeta = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)

      var videoCodec: String? = null
      var audioCodec: String? = null
      var fps: Double? = null
      var hasAudioFromExtractor = false

      val extractor = MediaExtractor()
      try {
        extractor.setDataSource(path)
        for (i in 0 until extractor.trackCount) {
          val format = extractor.getTrackFormat(i)
          val mime = if (format.containsKey(MediaFormat.KEY_MIME)) format.getString(MediaFormat.KEY_MIME) else null
          when {
            mime?.startsWith("video/") == true -> {
              videoCodec = mime.substringAfter('/')
              if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                fps = try {
                  format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                } catch (_: Exception) {
                  null
                }
              }
            }
            mime?.startsWith("audio/") == true -> {
              audioCodec = mime.substringAfter('/')
              hasAudioFromExtractor = true
            }
          }
        }
      } catch (_: Exception) {
        // Track-level detail is best-effort; the retriever-derived fields
        // above are still returned.
      } finally {
        extractor.release()
      }

      val container = File(path).extension.lowercase().ifEmpty { null }
      val hasAudio = when (hasAudioMeta) {
        "yes" -> true
        "no" -> false
        else -> hasAudioFromExtractor
      }

      MediaInfoMessage(
        mediaType = MediaTypeWire.VIDEO,
        width = width,
        height = height,
        format = container,
        sizeBytes = sizeBytes,
        durationMs = durationMs,
        fps = fps,
        bitrateBps = bitrateBps,
        videoCodec = videoCodec,
        audioCodec = audioCodec,
        container = container,
        hasAudio = hasAudio,
      )
    } catch (_: Exception) {
      null
    } finally {
      retriever.release()
    }
  }
}
