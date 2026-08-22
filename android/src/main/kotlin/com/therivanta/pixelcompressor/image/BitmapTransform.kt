package com.therivanta.pixelcompressor.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import kotlin.math.max
import kotlin.math.roundToInt

/** Decode/rotate/resize helpers shared by [ImageEngine] and
 * `thumbnail/ThumbnailEngine.kt`.
 */
object BitmapTransform {

  data class Bounds(val width: Int, val height: Int)

  /** Reads only the source's pixel dimensions, without allocating a
   * full bitmap.
   */
  fun decodeBounds(path: String): Bounds {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, options)
    if (options.outWidth <= 0 || options.outHeight <= 0) {
      throw PixelCompressorErrors.decodingError("Could not read image dimensions for $path")
    }
    return Bounds(options.outWidth, options.outHeight)
  }

  /** Decodes [path] into a [Bitmap], downsampling via `inSampleSize` so the
   * decoded bitmap is not much larger than [reqEdgePx] on its longest side
   * (a generous pre-scale; exact fitting happens afterward via
   * [fitToBox]). `null` decodes at full resolution.
   */
  fun decodeSampledBitmap(path: String, reqEdgePx: Int?): Bitmap {
    val bounds = decodeBounds(path)
    val sampleSize = if (reqEdgePx == null) {
      1
    } else {
      computeInSampleSize(bounds.width, bounds.height, reqEdgePx, reqEdgePx)
    }
    val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
    return BitmapFactory.decodeFile(path, options)
      ?: throw PixelCompressorErrors.decodingError("Failed to decode bitmap for $path")
  }

  private fun computeInSampleSize(
    rawWidth: Int,
    rawHeight: Int,
    reqWidth: Int,
    reqHeight: Int,
  ): Int {
    var inSampleSize = 1
    if (rawHeight > reqHeight || rawWidth > reqWidth) {
      val halfHeight = rawHeight / 2
      val halfWidth = rawWidth / 2
      while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
        inSampleSize *= 2
      }
    }
    return inSampleSize
  }

  /** Rotates [bitmap] by [degrees] (must be a multiple of 90), recycling
   * the input if a new bitmap was created.
   */
  fun rotate(bitmap: Bitmap, degrees: Int): Bitmap {
    if (degrees % 360 == 0) return bitmap
    val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
    val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    if (rotated !== bitmap) bitmap.recycle()
    return rotated
  }

  /** Scales [bitmap] down (never up) so it fits within [maxWidth] x
   * [maxHeight], aspect ratio preserved. Either bound `null` means
   * unconstrained on that axis. No-op if the bitmap already fits.
   */
  fun fitToBox(bitmap: Bitmap, maxWidth: Int?, maxHeight: Int?): Bitmap {
    if (maxWidth == null && maxHeight == null) return bitmap
    val widthScale = maxWidth?.let { it.toDouble() / bitmap.width } ?: Double.MAX_VALUE
    val heightScale = maxHeight?.let { it.toDouble() / bitmap.height } ?: Double.MAX_VALUE
    val scale = minOf(widthScale, heightScale, 1.0)
    if (scale >= 1.0) return bitmap
    val newWidth = max(1, (bitmap.width * scale).roundToInt())
    val newHeight = max(1, (bitmap.height * scale).roundToInt())
    val scaled = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    if (scaled !== bitmap) bitmap.recycle()
    return scaled
  }

  /** Scales [bitmap] down (never up) so its longest edge is at most
   * [maxEdgePx]. Used by the image target-size resolution-stepping loop.
   */
  fun fitLongestEdge(bitmap: Bitmap, maxEdgePx: Int): Bitmap =
    fitToBox(bitmap, maxEdgePx, maxEdgePx)
}
