package com.therivanta.pixelcompressor.image.exif

import android.content.Context
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.UUID

/// Copies EXIF from a source image onto a re-encoded output.
///
/// Both constructors throw [IOException] when the source has no readable EXIF
/// container.
class ExifKeeper private constructor(private val oldExif: ExifInterface) {

    @Throws(IOException::class)
    constructor(filePath: String) : this(ExifInterface(filePath))

    @Throws(IOException::class)
    constructor(buf: ByteArray) : this(ExifInterface(ByteArrayInputStream(buf)))

    fun writeToOutputStream(context: Context, outputStream: ByteArrayOutputStream): ByteArrayOutputStream {
        val file = File(context.cacheDir, "${UUID.randomUUID()}.jpg")
        try {
            file.writeBytes(outputStream.toByteArray())
            val newExif = ExifInterface(file.absolutePath)
            copyExif(oldExif, newExif)
            newExif.saveAttributes()
            return ByteArrayOutputStream().apply { write(file.readBytes()) }
        } catch (ex: Exception) {
            Log.e("ExifDataCopier", "Error preserving Exif data on selected image: $ex")
        } finally {
            file.delete()
        }
        return outputStream
    }

    fun copyExifToFile(file: File) {
        try {
            val newExif = ExifInterface(file.absolutePath)
            copyExif(oldExif, newExif)
            newExif.saveAttributes()
        } catch (ignored: IOException) {
        }
    }

    companion object {
        // Tags copied from the source image to the re-encoded output. We reference
        // ExifInterface.TAG_* constants (compile-time strings) so the list stays in
        // sync with the library. We intentionally skip:
        //   - fields invalidated by re-encoding / resizing:
        //       TAG_IMAGE_WIDTH, TAG_IMAGE_LENGTH, TAG_PIXEL_X_DIMENSION,
        //       TAG_PIXEL_Y_DIMENSION
        //   - JPEG structural fields the encoder rewrites:
        //       TAG_BITS_PER_SAMPLE, TAG_COMPRESSION, TAG_SAMPLES_PER_PIXEL,
        //       TAG_ROWS_PER_STRIP, TAG_STRIP_BYTE_COUNTS, TAG_STRIP_OFFSETS,
        //       TAG_PHOTOMETRIC_INTERPRETATION, TAG_PLANAR_CONFIGURATION
        //   - thumbnail pointers/data:
        //       TAG_JPEG_INTERCHANGE_FORMAT, TAG_JPEG_INTERCHANGE_FORMAT_LENGTH,
        //       and all TAG_THUMBNAIL_*
        private val attributes = listOf(
            // Descriptive / authorship
            ExifInterface.TAG_IMAGE_DESCRIPTION,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_ARTIST,
            ExifInterface.TAG_COPYRIGHT,
            ExifInterface.TAG_USER_COMMENT,

            // Orientation and resolution
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.TAG_X_RESOLUTION,
            ExifInterface.TAG_Y_RESOLUTION,
            ExifInterface.TAG_RESOLUTION_UNIT,
            ExifInterface.TAG_Y_CB_CR_POSITIONING,

            // Date/time
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME,
            ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
            ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
            ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
            ExifInterface.TAG_OFFSET_TIME_DIGITIZED,

            // Exposure / capture parameters
            ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_F_NUMBER,
            ExifInterface.TAG_EXPOSURE_PROGRAM,
            ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
            ExifInterface.TAG_SHUTTER_SPEED_VALUE,
            ExifInterface.TAG_APERTURE_VALUE,
            ExifInterface.TAG_BRIGHTNESS_VALUE,
            ExifInterface.TAG_EXPOSURE_BIAS_VALUE,
            ExifInterface.TAG_MAX_APERTURE_VALUE,
            ExifInterface.TAG_SUBJECT_DISTANCE,
            ExifInterface.TAG_METERING_MODE,
            ExifInterface.TAG_LIGHT_SOURCE,
            ExifInterface.TAG_FLASH,
            ExifInterface.TAG_FOCAL_LENGTH,
            ExifInterface.TAG_FLASH_ENERGY,
            ExifInterface.TAG_EXPOSURE_INDEX,
            ExifInterface.TAG_SENSITIVITY_TYPE,
            ExifInterface.TAG_EXPOSURE_MODE,
            ExifInterface.TAG_WHITE_BALANCE,
            ExifInterface.TAG_DIGITAL_ZOOM_RATIO,
            ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
            ExifInterface.TAG_SCENE_CAPTURE_TYPE,
            ExifInterface.TAG_GAIN_CONTROL,
            ExifInterface.TAG_CONTRAST,
            ExifInterface.TAG_SATURATION,
            ExifInterface.TAG_SHARPNESS,
            ExifInterface.TAG_SUBJECT_DISTANCE_RANGE,

            // EXIF metadata versions / color space
            ExifInterface.TAG_EXIF_VERSION,
            ExifInterface.TAG_FLASHPIX_VERSION,
            ExifInterface.TAG_COLOR_SPACE,
            ExifInterface.TAG_COMPONENTS_CONFIGURATION,

            // Camera lens
            ExifInterface.TAG_LENS_MAKE,
            ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_LENS_SERIAL_NUMBER,
            ExifInterface.TAG_LENS_SPECIFICATION,
            ExifInterface.TAG_BODY_SERIAL_NUMBER,
            ExifInterface.TAG_CAMERA_OWNER_NAME,

            // Image identifiers
            ExifInterface.TAG_IMAGE_UNIQUE_ID,

            // GPS
            ExifInterface.TAG_GPS_VERSION_ID,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_TIMESTAMP,
            ExifInterface.TAG_GPS_DATESTAMP,
            ExifInterface.TAG_GPS_SATELLITES,
            ExifInterface.TAG_GPS_STATUS,
            ExifInterface.TAG_GPS_MEASURE_MODE,
            ExifInterface.TAG_GPS_DOP,
            ExifInterface.TAG_GPS_SPEED,
            ExifInterface.TAG_GPS_SPEED_REF,
            ExifInterface.TAG_GPS_TRACK,
            ExifInterface.TAG_GPS_TRACK_REF,
            ExifInterface.TAG_GPS_IMG_DIRECTION,
            ExifInterface.TAG_GPS_IMG_DIRECTION_REF,
            ExifInterface.TAG_GPS_MAP_DATUM,
            ExifInterface.TAG_GPS_DEST_LATITUDE,
            ExifInterface.TAG_GPS_DEST_LATITUDE_REF,
            ExifInterface.TAG_GPS_DEST_LONGITUDE,
            ExifInterface.TAG_GPS_DEST_LONGITUDE_REF,
            ExifInterface.TAG_GPS_DEST_BEARING,
            ExifInterface.TAG_GPS_DEST_BEARING_REF,
            ExifInterface.TAG_GPS_DEST_DISTANCE,
            ExifInterface.TAG_GPS_DEST_DISTANCE_REF,
            ExifInterface.TAG_GPS_PROCESSING_METHOD,
            ExifInterface.TAG_GPS_AREA_INFORMATION,
            ExifInterface.TAG_GPS_DIFFERENTIAL,
            ExifInterface.TAG_GPS_H_POSITIONING_ERROR,
        )

        private fun copyExif(oldExif: ExifInterface, newExif: ExifInterface) {
            for (attribute in attributes) {
                oldExif.getAttribute(attribute)?.let { newExif.setAttribute(attribute, it) }
            }
            // Output pixels are re-encoded in display orientation by the pipeline
            // (BitmapFactory decode + optional Bitmap.rotate before compress), so the
            // source's TAG_ORIENTATION must not carry over — otherwise viewers double-rotate.
            newExif.setAttribute(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL.toString(),
            )
            try {
                newExif.saveAttributes()
            } catch (ignored: IOException) {
            }
        }
    }
}
