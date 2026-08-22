package com.therivanta.pixelcompressor.image

import android.graphics.Bitmap
import androidx.heifwriter.HeifWriter
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors

/** Thin wrapper around `androidx.heifwriter.HeifWriter` for single-bitmap
 * HEIC encoding. Requires a hardware HEVC encoder on the device — callers
 * must check [com.therivanta.pixelcompressor.capability.CapabilityProbe.isHevcSupported]
 * and throw `unsupported_codec` *before* calling this, per the plugin's
 * "never silently substitute a codec" contract.
 */
object HeicWriterSupport {

  private const val STOP_TIMEOUT_MS = 5_000

  fun encode(bitmap: Bitmap, outputPath: String, quality: Int) {
    val writer = try {
      HeifWriter.Builder(outputPath, bitmap.width, bitmap.height, HeifWriter.INPUT_MODE_BITMAP)
        .setQuality(quality)
        .setMaxImages(1)
        .setPrimaryIndex(0)
        .build()
    } catch (e: Exception) {
      throw PixelCompressorErrors.encodingError("Failed to initialize HEIC encoder: ${e.message}", e.toString())
    }

    try {
      writer.start()
      writer.addBitmap(bitmap)
      writer.stop(STOP_TIMEOUT_MS.toLong())
    } catch (e: Exception) {
      throw PixelCompressorErrors.encodingError("HEIC encoding failed: ${e.message}", e.toString())
    } finally {
      writer.close()
    }
  }
}
