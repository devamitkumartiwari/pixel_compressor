package com.therivanta.pixelcompressor.image.handle.heif

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import androidx.heifwriter.HeifWriter
import com.therivanta.pixelcompressor.image.ext.ResizeSpec
import com.therivanta.pixelcompressor.image.ext.calcScale
import com.therivanta.pixelcompressor.image.ext.fitTo
import com.therivanta.pixelcompressor.image.ext.preferSrgb
import com.therivanta.pixelcompressor.image.ext.rotate
import com.therivanta.pixelcompressor.image.handle.FormatHandler
import com.therivanta.pixelcompressor.image.logger.log
import com.therivanta.pixelcompressor.image.util.TmpFileUtil
import java.io.OutputStream

class HeifHandler : FormatHandler {
    override val type: Int
        get() = 2
    override val typeName: String
        get() = "heif"

    override fun handleByteArray(
        context: Context,
        byteArray: ByteArray,
        outputStream: OutputStream,
        minWidth: Int,
        minHeight: Int,
        quality: Int,
        rotate: Int,
        keepExif: Boolean,
        inSampleSize: Int,
        resize: ResizeSpec,
    ) {
        val tmpFile = TmpFileUtil.createTmpFile(context)
        try {
            compress(byteArray, minWidth, minHeight, quality, rotate, inSampleSize, tmpFile.absolutePath, resize)
            // Warn only after compression actually produced a HEIC — otherwise
            // a HeifWriter failure (OOM, missing hardware encoder) gets
            // misattributed to the keepExif path in bug triage.
            warnKeepExifUnsupported(keepExif)
            outputStream.write(tmpFile.readBytes())
        } finally {
            tmpFile.delete()
        }
    }

    private fun compress(
        arr: ByteArray,
        minWidth: Int,
        minHeight: Int,
        quality: Int,
        rotate: Int = 0,
        inSampleSize: Int,
        targetPath: String,
        resize: ResizeSpec,
    ) {
        val options = makeOption(inSampleSize)
        val bitmap = BitmapFactory.decodeByteArray(arr, 0, arr.count(), options)
        convertToHeif(bitmap, minWidth, minHeight, rotate, targetPath, quality, resize)
    }

    private fun compress(
        path: String,
        minWidth: Int,
        minHeight: Int,
        quality: Int,
        rotate: Int = 0,
        inSampleSize: Int,
        targetPath: String,
        resize: ResizeSpec,
    ) {
        val options = makeOption(inSampleSize)
        val bitmap = BitmapFactory.decodeFile(path, options)
        convertToHeif(bitmap, minWidth, minHeight, rotate, targetPath, quality, resize)
    }

    private fun makeOption(inSampleSize: Int): BitmapFactory.Options {
        val options = BitmapFactory.Options().preferSrgb()
        options.inJustDecodeBounds = false
        options.inPreferredConfig = Bitmap.Config.ARGB_8888
        options.inSampleSize = inSampleSize
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            options.inDither = true
        }
        return options
    }

    private fun convertToHeif(
        bitmap: Bitmap,
        minWidth: Int,
        minHeight: Int,
        rotate: Int,
        targetPath: String,
        quality: Int,
        resize: ResizeSpec,
    ) {
        val w = bitmap.width.toFloat()
        val h = bitmap.height.toFloat()
        log("src width = $w")
        log("src height = $h")
        val scale = bitmap.calcScale(minWidth, minHeight, resize, rotate)
        log("scale = $scale")
        val destW = w / scale
        val destH = h / scale
        log("dst width = $destW")
        log("dst height = $destH")
        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            destW.toInt(),
            destH.toInt(),
            true
        )
        val turned = scaled.rotate(rotate)
        val result = turned.fitTo(resize)
        try {
            val heifWriter = HeifWriter.Builder(
                targetPath,
                result.width,
                result.height,
                HeifWriter.INPUT_MODE_BITMAP
            ).setQuality(quality).setMaxImages(1).build()
            try {
                heifWriter.start()
                heifWriter.addBitmap(result)
                heifWriter.stop(5000)
            } finally {
                heifWriter.close()
            }
        } finally {
            if (result !== turned) {
                result.recycle()
            }
            if (turned !== scaled) {
                turned.recycle()
            }
            if (scaled !== bitmap) {
                scaled.recycle()
            }
            bitmap.recycle()
        }
    }

    override fun handleFile(
        context: Context,
        path: String,
        outputStream: OutputStream,
        minWidth: Int,
        minHeight: Int,
        quality: Int,
        rotate: Int,
        keepExif: Boolean,
        inSampleSize: Int,
        numberOfRetries: Int,
        resize: ResizeSpec,
    ) {
        val tmpFile = TmpFileUtil.createTmpFile(context)
        try {
            compress(path, minWidth, minHeight, quality, rotate, inSampleSize, tmpFile.absolutePath, resize)
            warnKeepExifUnsupported(keepExif)
            outputStream.write(tmpFile.readBytes())
        } finally {
            tmpFile.delete()
        }
    }

    // The `keepExif` parameter used to be silently ignored on the HEIC path
    // (parameter received, never read). That is still the runtime behaviour,
    // but is now discoverable via Log.w (which surfaces to `adb logcat`
    // regardless of the plugin's `showLog` flag): androidx.exifinterface
    // refuses to write EXIF to HEIF/HEIC containers ("ExifInterface only
    // supports saving attributes for JPEG, PNG, and WebP formats"), and
    // Android does not ship an alternative library that authors HEIF
    // metadata boxes. Manual ISO/IEC 23008-12 box injection would be
    // ~400 LOC and is left for a follow-up.
    // Users asking for `keepExif=true` on HEIC get a valid HEIC without
    // EXIF instead of a crash or malformed output. See README's
    // "keepExif" section for the platform matrix.
    private fun warnKeepExifUnsupported(keepExif: Boolean) {
        if (keepExif) {
            Log.w(
                "PixelImageCompressor",
                "keepExif=true is not supported for HEIC output on Android " +
                        "(androidx.exifinterface cannot save attributes to HEIF/HEIC). " +
                        "The compressed HEIC is valid but does not carry EXIF metadata."
            )
        }
    }
}