package com.therivanta.pixelcompressor.util

import com.therivanta.pixelcompressor.errors.PixelCompressorErrors

/** Shared rotation-combination helper used by the image and video engines:
 * combines the source's own baked-in rotation (EXIF orientation degrees for
 * images, track rotation for video) with the caller-requested additional
 * rotation, normalized to `[0, 360)`.
 */
object RotationMath {
  /**
   * @throws com.therivanta.pixelcompressor.FlutterError if [requestedDegrees]
   *   isn't one of 0/90/180/270. The public Dart API only documents and
   *   `assert()`s that contract — an assert that's compiled out of release
   *   builds — so this is the actual enforcement: both the video (GL
   *   position-matrix rotation) and image (bitmap canvas rotation) pipelines
   *   downstream only handle rotation in 90-degree steps, and silently
   *   produce wrong pixels (video) or a clipped canvas (image) for anything
   *   else.
   */
  fun combineRotation(sourceDegrees: Int, requestedDegrees: Int): Int {
    if (requestedDegrees != 0 && requestedDegrees != 90 && requestedDegrees != 180 && requestedDegrees != 270) {
      throw PixelCompressorErrors.invalidMedia(
        "rotationDegrees must be one of 0, 90, 180, 270, got $requestedDegrees",
      )
    }
    val total = (sourceDegrees + requestedDegrees) % 360
    return if (total < 0) total + 360 else total
  }
}
