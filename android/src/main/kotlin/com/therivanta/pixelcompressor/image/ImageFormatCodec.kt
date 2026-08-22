package com.therivanta.pixelcompressor.image

import android.graphics.Bitmap
import android.os.Build
import com.therivanta.pixelcompressor.ImageFormatWire
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import java.io.ByteArrayOutputStream
import java.io.File

/** Maps the wire [ImageFormatWire] enum to Android encode mechanics:
 * `Bitmap.compress` for JPEG/PNG/WebP, [HeicWriterSupport] for HEIC.
 */
object ImageFormatCodec {

  fun extensionFor(format: ImageFormatWire): String = when (format) {
    ImageFormatWire.JPEG -> "jpg"
    ImageFormatWire.PNG -> "png"
    ImageFormatWire.WEBP -> "webp"
    ImageFormatWire.HEIC -> "heic"
  }

  fun wireNameFor(format: ImageFormatWire): String = when (format) {
    ImageFormatWire.JPEG -> "jpeg"
    ImageFormatWire.PNG -> "png"
    ImageFormatWire.WEBP -> "webp"
    ImageFormatWire.HEIC -> "heic"
  }

  /** Best-effort format detection from a source file's extension, used
   * when the request doesn't specify an output format (keep source
   * format). Defaults to JPEG for unrecognized/absent extensions.
   */
  fun detectFromPath(path: String): ImageFormatWire {
    return when (File(path).extension.lowercase()) {
      "png" -> ImageFormatWire.PNG
      "webp" -> ImageFormatWire.WEBP
      "heic", "heif" -> ImageFormatWire.HEIC
      else -> ImageFormatWire.JPEG
    }
  }

  private fun bitmapCompressFormat(format: ImageFormatWire): Bitmap.CompressFormat = when (format) {
    ImageFormatWire.JPEG -> Bitmap.CompressFormat.JPEG
    ImageFormatWire.PNG -> Bitmap.CompressFormat.PNG
    ImageFormatWire.WEBP -> {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        @Suppress("DEPRECATION")
        Bitmap.CompressFormat.WEBP_LOSSY
      } else {
        @Suppress("DEPRECATION")
        Bitmap.CompressFormat.WEBP
      }
    }
    ImageFormatWire.HEIC -> throw IllegalArgumentException("HEIC is not a Bitmap.compress format")
  }

  /** Encodes [bitmap] at [quality] (1-100) into an in-memory byte array,
   * using [scratchDir] for a temp file when the format (HEIC) requires
   * writing to a path rather than a stream.
   */
  fun encode(bitmap: Bitmap, format: ImageFormatWire, quality: Int, scratchDir: File): ByteArray {
    return if (format == ImageFormatWire.HEIC) {
      val scratchFile = File.createTempFile("pc_heic_attempt", ".heic", scratchDir)
      try {
        HeicWriterSupport.encode(bitmap, scratchFile.absolutePath, quality)
        scratchFile.readBytes()
      } finally {
        scratchFile.delete()
      }
    } else {
      val stream = ByteArrayOutputStream()
      val ok = bitmap.compress(bitmapCompressFormat(format), quality, stream)
      if (!ok) {
        throw PixelCompressorErrors.encodingError("Bitmap.compress returned false for format $format")
      }
      stream.toByteArray()
    }
  }
}
