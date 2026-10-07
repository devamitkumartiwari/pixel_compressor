package com.therivanta.pixelcompressor.image.core

import android.content.Context
import com.therivanta.pixelcompressor.image.ImageCompressHandler
import com.therivanta.pixelcompressor.image.exception.CompressError
import com.therivanta.pixelcompressor.image.exif.Exif
import com.therivanta.pixelcompressor.image.ext.ResizeSpec
import com.therivanta.pixelcompressor.image.format.FormatRegister
import com.therivanta.pixelcompressor.image.logger.log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class CompressListHandler(private val call: MethodCall, result: MethodChannel.Result) : ResultHandler(result) {
    fun handle(context: Context) {
        threadPool.execute {
            @Suppress("UNCHECKED_CAST") val args: List<Any> = call.arguments as List<Any>
            val arr = args[0] as ByteArray
            var minWidth = args[1] as Int
            var minHeight = args[2] as Int
            val quality = args[3] as Int
            val rotate = args[4] as Int
            val autoCorrectionAngle = args[5] as Boolean
            val format = args[6] as Int
            val keepExif = args[7] as Boolean
            val inSampleSize = args[8] as Int
            var resize = ResizeSpec.fromArgs(args, 9)
            val exifRotate = if (autoCorrectionAngle) Exif.getRotationDegrees(arr) else 0
            if (exifRotate == 270 || exifRotate == 90) {
                val tmp = minWidth
                minWidth = minHeight
                minHeight = tmp
                resize = resize.swapMaxBounds()
            }
            val formatHandler = FormatRegister.findFormat(format)
            if (formatHandler == null) {
                log("No support format.")
                replyError("unsupported_format", "No handler for format=$format")
                return@execute
            }
            val targetRotate = rotate + exifRotate
            val outputStream = ByteArrayOutputStream()
            try {
                formatHandler.handleByteArray(
                    context,
                    arr,
                    outputStream,
                    minWidth,
                    minHeight,
                    quality,
                    targetRotate,
                    keepExif,
                    inSampleSize,
                    resize,
                )
                reply(outputStream.toByteArray())
            } catch (e: CompressError) {
                log(e.message)
                if (ImageCompressHandler.showLog) e.printStackTrace()
                replyError("encode_failed", e.message ?: "compress failed")
            } catch (e: Exception) {
                if (ImageCompressHandler.showLog) e.printStackTrace()
                replyError("unknown", e.message ?: "compress failed")
            } finally {
                outputStream.close()
            }
        }
    }
}
