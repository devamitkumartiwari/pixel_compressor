package com.therivanta.pixelcompressor.image.handle.common

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.therivanta.pixelcompressor.image.exif.ExifKeeper
import com.therivanta.pixelcompressor.image.ext.ResizeSpec
import com.therivanta.pixelcompressor.image.ext.calcScale
import com.therivanta.pixelcompressor.image.ext.fitTo
import com.therivanta.pixelcompressor.image.ext.compress
import com.therivanta.pixelcompressor.image.ext.forQuality
import com.therivanta.pixelcompressor.image.ext.preferSrgb
import com.therivanta.pixelcompressor.image.ext.rotate
import com.therivanta.pixelcompressor.image.handle.FormatHandler
import com.therivanta.pixelcompressor.image.logger.log
import java.io.ByteArrayOutputStream
import java.io.OutputStream

class CommonHandler(override val type: Int) : FormatHandler {
    override val typeName: String = when (type) {
        1 -> "png"
        3 -> "webp"
        else -> "jpeg"
    }

    @Suppress("DEPRECATION")
    private val bitmapFormat: Bitmap.CompressFormat = when (type) {
        1 -> Bitmap.CompressFormat.PNG
        3 -> Bitmap.CompressFormat.WEBP
        else -> Bitmap.CompressFormat.JPEG
    }

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
        val result = compress(byteArray, minWidth, minHeight, quality, rotate, inSampleSize, resize)
        if (keepExif && supportsExifWrite(bitmapFormat)) {
            // ExifKeeper writes to a tmp file and opens it via
            // ExifInterface(path). ExifInterface sniffs the container from
            // magic bytes, not the tmp filename's extension, so the same
            // ExifKeeper path works for JPEG, PNG, and WebP outputs.
            //
            // If the SOURCE bytes don't carry readable EXIF (corrupt file,
            // odd container), ExifKeeper's constructor throws IOException.
            // Fall back to the raw compressed bytes without EXIF — the
            // whole compression call must never fail just because there
            // was no source metadata to copy.
            outputStream.write(runExifKeeperOrRaw(context, result) {
                ExifKeeper(byteArray)
            })
        } else {
            outputStream.write(result)
        }
    }

    private fun compress(
        arr: ByteArray,
        minWidth: Int,
        minHeight: Int,
        quality: Int,
        rotate: Int = 0,
        inSampleSize: Int,
        resize: ResizeSpec,
    ): ByteArray {
        val options = BitmapFactory.Options().preferSrgb()
        options.inJustDecodeBounds = false
        options.inPreferredConfig = Bitmap.Config.ARGB_8888
        options.inSampleSize = inSampleSize
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            options.inDither = true
        }
        val bitmap = BitmapFactory.decodeByteArray(arr, 0, arr.count(), options)
        val outputStream = ByteArrayOutputStream()
        try {
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
                bitmap, destW.toInt(),
                destH.toInt(),
                true
            )
            val turned = scaled.rotate(rotate)
            val rotated = turned.fitTo(resize)
            try {
                rotated.compress(bitmapFormat.forQuality(quality), quality, outputStream)
            } finally {
                if (rotated !== turned) rotated.recycle()
                if (turned !== scaled) turned.recycle()
                if (scaled !== bitmap) scaled.recycle()
            }
        } finally {
            bitmap.recycle()
        }
        return outputStream.toByteArray()
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
        try {
            if (numberOfRetries <= 0) return;
            val options = BitmapFactory.Options().preferSrgb()
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.ARGB_8888
            options.inSampleSize = inSampleSize
            if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                options.inDither = true
            }
            val bitmap = BitmapFactory.decodeFile(path, options)
            val array = try {
                bitmap.compress(minWidth, minHeight, quality, rotate, type, resize)
            } finally {
                bitmap.recycle()
            }
            if (keepExif && supportsExifWrite(bitmapFormat)) {
                // See handleByteArray for the format-guard rationale.
                outputStream.write(runExifKeeperOrRaw(context, array) {
                    ExifKeeper(path)
                })
            } else {
                outputStream.write(array)
            }
        } catch (e: OutOfMemoryError) {//handling out of memory error and increase samples size
            System.gc();
            handleFile(
                context,
                path,
                outputStream,
                minWidth,
                minHeight,
                quality,
                rotate,
                keepExif,
                inSampleSize * 2,
                numberOfRetries - 1,
                resize,
            );
        }
    }

    // androidx.exifinterface's `saveAttributes()` accepts JPEG, PNG, and
    // WebP output containers (the underlying error for anything else is
    // "ExifInterface only supports saving attributes for JPEG, PNG, and
    // WebP formats"). WebP-writer correctness requires 1.3.7+ (see the
    // dependency-version comment in android/build.gradle.kts). Enumerating
    // explicitly instead of `!= HEIC` protects us if Android adds another
    // `Bitmap.CompressFormat` value in a future SDK — new formats stay ❌ until proven supported.
    @Suppress("DEPRECATION")
    private fun supportsExifWrite(format: Bitmap.CompressFormat): Boolean =
        format == Bitmap.CompressFormat.JPEG ||
                format == Bitmap.CompressFormat.PNG ||
                format == Bitmap.CompressFormat.WEBP

    // ExifKeeper's constructor calls `new ExifInterface(ByteArrayInputStream)`
    // (or `ExifInterface(String path)`) which throws IOException when the
    // source is corrupt or a container ExifInterface doesn't understand.
    // Fall back to the raw compressed bytes without EXIF instead of
    // propagating the exception — the whole compression call must never
    // fail just because there was no source metadata to copy.
    private inline fun runExifKeeperOrRaw(
        context: Context,
        raw: ByteArray,
        makeKeeper: () -> ExifKeeper
    ): ByteArray {
        val keeper = try {
            makeKeeper()
        } catch (e: Exception) {
            log("keepExif=true: could not read source EXIF, falling back to raw compressed bytes: $e")
            return raw
        }
        val buffer = ByteArrayOutputStream()
        buffer.write(raw)
        return keeper.writeToOutputStream(context, buffer).toByteArray()
    }
}
