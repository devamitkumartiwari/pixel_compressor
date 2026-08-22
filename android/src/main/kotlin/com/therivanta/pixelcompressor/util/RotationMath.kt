package com.therivanta.pixelcompressor.util

/** Shared rotation-combination helper used by the image, video, and
 * thumbnail engines: combines the source's own baked-in rotation (EXIF
 * orientation degrees for images, track rotation for video) with the
 * caller-requested additional rotation, normalized to `[0, 360)`.
 */
object RotationMath {
  fun combineRotation(sourceDegrees: Int, requestedDegrees: Int): Int {
    val total = (sourceDegrees + requestedDegrees) % 360
    return if (total < 0) total + 360 else total
  }
}
