package com.therivanta.pixelcompressor.image

import androidx.exifinterface.media.ExifInterface

/** EXIF orientation reading and tag-copying helpers.
 *
 * Orientation-to-degrees mapping (the EXIF spec's 8 values collapse to the
 * 4 multiples-of-90 this plugin supports; flipped variants are treated as
 * their non-flipped rotation since we don't mirror pixels):
 */
object ExifSupport {

  private val ORIENTATION_TO_DEGREES = mapOf(
    ExifInterface.ORIENTATION_NORMAL to 0,
    ExifInterface.ORIENTATION_ROTATE_90 to 90,
    ExifInterface.ORIENTATION_ROTATE_180 to 180,
    ExifInterface.ORIENTATION_ROTATE_270 to 270,
    ExifInterface.ORIENTATION_TRANSPOSE to 90,
    ExifInterface.ORIENTATION_FLIP_HORIZONTAL to 0,
    ExifInterface.ORIENTATION_TRANSVERSE to 270,
    ExifInterface.ORIENTATION_FLIP_VERTICAL to 180,
    ExifInterface.ORIENTATION_UNDEFINED to 0,
  )

  /** Tags copied from source to output when [ExifPolicy.keep] is
   * requested. Deliberately excludes ORIENTATION (always forced to
   * normal on the output, since pixels are already baked upright) and
   * nothing else is excluded — GPS tags are copied too because "keep"
   * means keep, `strip` is the policy for callers who don't want that.
   */
  private val COPYABLE_TAGS = listOf(
    ExifInterface.TAG_MAKE,
    ExifInterface.TAG_MODEL,
    ExifInterface.TAG_DATETIME,
    ExifInterface.TAG_DATETIME_DIGITIZED,
    ExifInterface.TAG_DATETIME_ORIGINAL,
    ExifInterface.TAG_EXPOSURE_TIME,
    ExifInterface.TAG_F_NUMBER,
    ExifInterface.TAG_ISO_SPEED_RATINGS,
    ExifInterface.TAG_FOCAL_LENGTH,
    ExifInterface.TAG_WHITE_BALANCE,
    ExifInterface.TAG_FLASH,
    ExifInterface.TAG_APERTURE_VALUE,
    ExifInterface.TAG_SHUTTER_SPEED_VALUE,
    ExifInterface.TAG_GPS_LATITUDE,
    ExifInterface.TAG_GPS_LATITUDE_REF,
    ExifInterface.TAG_GPS_LONGITUDE,
    ExifInterface.TAG_GPS_LONGITUDE_REF,
    ExifInterface.TAG_GPS_ALTITUDE,
    ExifInterface.TAG_GPS_ALTITUDE_REF,
    ExifInterface.TAG_GPS_TIMESTAMP,
    ExifInterface.TAG_GPS_DATESTAMP,
    ExifInterface.TAG_ARTIST,
    ExifInterface.TAG_COPYRIGHT,
    ExifInterface.TAG_IMAGE_DESCRIPTION,
    ExifInterface.TAG_LENS_MAKE,
    ExifInterface.TAG_LENS_MODEL,
  )

  fun readOrientationDegrees(path: String): Int {
    return try {
      val exif = ExifInterface(path)
      val orientation = exif.getAttributeInt(
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.ORIENTATION_NORMAL,
      )
      ORIENTATION_TO_DEGREES[orientation] ?: 0
    } catch (_: Exception) {
      0
    }
  }

  fun hasExif(path: String): Boolean {
    return try {
      val exif = ExifInterface(path)
      COPYABLE_TAGS.any { exif.getAttribute(it) != null } ||
        exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) !=
        ExifInterface.ORIENTATION_NORMAL
    } catch (_: Exception) {
      false
    }
  }

  /** Copies [COPYABLE_TAGS] from [sourcePath] to [destPath] and forces the
   * output's orientation tag to normal (pixels are already baked upright
   * by the time this runs). Best-effort: output formats that
   * [ExifInterface] can't write to (some HEIC variants) fail silently
   * since EXIF preservation is a nice-to-have, not a required outcome.
   */
  fun copyExif(sourcePath: String, destPath: String) {
    try {
      val source = ExifInterface(sourcePath)
      val dest = ExifInterface(destPath)
      var wroteAny = false
      for (tag in COPYABLE_TAGS) {
        val value = source.getAttribute(tag) ?: continue
        dest.setAttribute(tag, value)
        wroteAny = true
      }
      dest.setAttribute(
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.ORIENTATION_NORMAL.toString(),
      )
      if (wroteAny) dest.saveAttributes()
    } catch (_: Exception) {
      // Best-effort — see kdoc above.
    }
  }
}
