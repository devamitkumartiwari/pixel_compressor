package com.therivanta.pixelcompressor.video

import android.content.Context
import android.graphics.Bitmap
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

class ThumbnailUtility(channelName: String) {
    private val utility = Utility(channelName)

    fun getByteThumbnail(path: String, quality: Int, position: Long, maxSize: Int, result: MethodChannel.Result) {
        val bmp = utility.getBitmap(path, position, maxSize, result) ?: return

        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        val byteArray = stream.toByteArray()
        bmp.recycle()
        result.success(byteArray)
    }

    fun getFileThumbnail(context: Context, path: String, quality: Int, position: Long,
                         maxSize: Int, result: MethodChannel.Result) {
        val bmp = utility.getBitmap(path, position, maxSize, result) ?: return

        val dir = Utility.cacheDir(context)

        // One file per (video, position) so extracting several frames doesn't
        // overwrite earlier thumbnails.
        val file = File(dir, "${File(path).nameWithoutExtension}_$position.jpg")
        utility.deleteFile(file)

        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        val byteArray = stream.toByteArray()

        try {
            file.createNewFile()
            file.writeBytes(byteArray)
        } catch (e: IOException) {
            e.printStackTrace()
        }

        bmp.recycle()

        result.success(file.absolutePath)
    }
}
