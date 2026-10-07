package com.therivanta.pixelcompressor.image.ext

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import android.graphics.Matrix
import android.os.Build
import com.therivanta.pixelcompressor.image.ImageCompressHandler
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import kotlin.math.max
import kotlin.math.min

fun Bitmap.compress(
    minWidth: Int,
    minHeight: Int,
    quality: Int,
    rotate: Int = 0,
    format: Int,
    resize: ResizeSpec = ResizeSpec.NONE,
): ByteArray {
    val outputStream = ByteArrayOutputStream()
    compress(minWidth, minHeight, quality, rotate, outputStream, format, resize)
    return outputStream.toByteArray()
}

fun Bitmap.compress(
    minWidth: Int,
    minHeight: Int,
    quality: Int,
    rotate: Int = 0,
    outputStream: OutputStream,
    format: Int = 0,
    resize: ResizeSpec = ResizeSpec.NONE,
) {
    val w = this.width.toFloat()
    val h = this.height.toFloat()
    log("src width = $w")
    log("src height = $h")
    val scale = calcScale(minWidth, minHeight, resize, rotate)
    log("scale = $scale")
    val destW = w / scale
    val destH = h / scale
    log("dst width = $destW")
    log("dst height = $destH")
    val scaled = Bitmap.createScaledBitmap(this, destW.toInt(), destH.toInt(), true)
    val turned = scaled.rotate(rotate)
    val rotated = turned.fitTo(resize)
    try {
        rotated.compress(convertFormatIndexToFormat(format).forQuality(quality), quality, outputStream)
    } finally {
        // Recycle in reverse order, but only when the instance is distinct
        // from its parent (createScaledBitmap, rotate and fitTo can
        // pass-through).
        if (rotated !== turned) {
            rotated.recycle()
        }
        if (turned !== scaled) {
            turned.recycle()
        }
        if (scaled !== this) {
            scaled.recycle()
        }
    }
}

private fun log(any: Any?) {
    if (ImageCompressHandler.showLog) {
        println(any ?: "null")
    }
}

fun Bitmap.rotate(rotate: Int): Bitmap {
    return if (rotate % 360 != 0) {
        val matrix = Matrix()
        matrix.setRotate(rotate.toFloat())
        // Rotate in place.
        Bitmap.createBitmap(this, 0, 0, width, height, matrix, false)
    } else {
        this
    }
}

fun Bitmap.calcScale(minWidth: Int, minHeight: Int): Float {
    val w = width.toFloat()
    val h = height.toFloat()
    val scaleW = w / minWidth.toFloat()
    val scaleH = h / minHeight.toFloat()
    log("width scale = $scaleW")
    log("height scale = $scaleH")
    return max(1f, min(scaleW, scaleH))
}

@Suppress("DEPRECATION")
fun convertFormatIndexToFormat(type: Int): Bitmap.CompressFormat {
    return when (type) {
        1 -> Bitmap.CompressFormat.PNG
        3 -> Bitmap.CompressFormat.WEBP
        else -> Bitmap.CompressFormat.JPEG
    }
}

/// `Bitmap.CompressFormat.WEBP` is deprecated since API 30. Its documented
/// behaviour (API 29+) is lossless at quality 100 and lossy otherwise, so map
/// it onto the explicit replacements to keep output identical.
@Suppress("DEPRECATION")
fun Bitmap.CompressFormat.forQuality(quality: Int): Bitmap.CompressFormat {
    if (this != Bitmap.CompressFormat.WEBP || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
        return this
    }
    return if (quality == 100) Bitmap.CompressFormat.WEBP_LOSSLESS else Bitmap.CompressFormat.WEBP_LOSSY
}

/// Decode into sRGB. Otherwise wide-gamut sources (Display P3 / Adobe RGB,
/// the default on recent Samsung cameras) keep their colour space, and
/// Bitmap.compress writes those pixels without an ICC profile, so most viewers
/// show the output oversaturated. Matches iOS, which already renders in sRGB.
fun BitmapFactory.Options.preferSrgb(): BitmapFactory.Options = apply {
    inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
}
