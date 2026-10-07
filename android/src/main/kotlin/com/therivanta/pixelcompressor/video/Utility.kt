package com.therivanta.pixelcompressor.video

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class Utility(private val channelName: String) {

    /// True for 90°/270°, where width and height must be swapped.
    fun isPortraitRotation(orientation: Int) = orientation == 90 || orientation == 270

    fun deleteFile(file: File) {
        if (file.exists()) {
            file.delete()
        }
    }

    fun timeStrToTimestamp(time: String): Long {
        val timeArr = time.split(":")
        val hour = Integer.parseInt(timeArr[0])
        val min = Integer.parseInt(timeArr[1])
        val secArr = timeArr[2].split(".")
        val sec = Integer.parseInt(secArr[0])
        val mSec = Integer.parseInt(secArr[1])

        val timeStamp = (hour * 3600 + min * 60 + sec) * 1000 + mSec
        return timeStamp.toLong()
    }

    fun getMediaInfoJson(context: Context, path: String): JSONObject {
        val file = File(path)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, Uri.fromFile(file))

            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
            val author = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_AUTHOR) ?: ""
            val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val duration = durationStr?.toLongOrNull() ?: 0L
            var width = widthStr?.toLongOrNull() ?: 0L
            var height = heightStr?.toLongOrNull() ?: 0L
            val filesize = file.length()
            val orientation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val ori = orientation?.toIntOrNull()
            if (ori != null && isPortraitRotation(ori)) {
                val tmp = width
                width = height
                height = tmp
            }

            val json = JSONObject()

            json.put("path", path)
            json.put("title", title)
            json.put("author", author)
            json.put("width", width)
            json.put("height", height)
            json.put("duration", duration)
            json.put("filesize", filesize)
            if (ori != null) {
                json.put("orientation", ori)
            }

            return json
        } finally {
            // Release on every path; leaking retrievers exhausts native fds.
            try {
                retriever.release()
            } catch (ex: Exception) {
                // Ignore failures while cleaning up.
            }
        }
    }

    /// Returns null after replying with an error, so callers must stop
    /// (replying twice, or using a null bitmap, would crash).
    fun getBitmap(path: String, position: Long, maxSize: Int, result: MethodChannel.Result): Bitmap? {
        var bitmap: Bitmap? = null
        var rotation = 0
        var rawWidth: Int? = null
        val retriever = MediaMetadataRetriever()

        try {
            retriever.setDataSource(path)
            // [position] is in milliseconds (Dart API); the retriever wants µs.
            // OPTION_CLOSEST returns the exact frame instead of snapping to
            // the previous keyframe.
            val timeUs = if (position < 0) -1L else position * 1000L
            bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                // Some decoders can't seek frame-exactly; fall back to the
                // nearest key frame rather than failing.
                ?: retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            rawWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
        } catch (ex: RuntimeException) {
            // IllegalArgumentException is a RuntimeException.
        } finally {
            try {
                retriever.release()
            } catch (ex: Exception) {
                // Ignore failures while cleaning up.
            }
        }

        if (bitmap == null) {
            result.error(channelName, "Assume this is a corrupt video file", null)
            return null
        }

        // AOSP already rotates the frame, but some OEM builds return it in
        // its encoded orientation. Only correct it when the frame still has
        // the raw (unrotated) dimensions, so stock devices aren't rotated twice.
        if (isPortraitRotation(rotation) && bitmap.width == rawWidth && bitmap.width != bitmap.height) {
            val matrix = Matrix().apply { setRotate(rotation.toFloat()) }
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }

        val width = bitmap.width
        val height = bitmap.height
        val max = Math.max(width, height)
        if (maxSize > 0 && max > maxSize) {
            val scale = maxSize.toFloat() / max
            val w = Math.round(scale * width)
            val h = Math.round(scale * height)
            bitmap = Bitmap.createScaledBitmap(bitmap, w, h, true)
        }

        return bitmap
    }

    fun getFileNameWithGifExtension(path: String): String {
        val file = File(path)
        var fileName = ""
        val gifSuffix = "gif"
        val dotGifSuffix = ".$gifSuffix"

        if (file.exists()) {
            val name = file.name
            fileName = name.replaceAfterLast(".", gifSuffix)

            if (!fileName.endsWith(dotGifSuffix)) {
                fileName += dotGifSuffix
            }
        }
        return fileName
    }

    fun deleteAllCache(context: Context): Boolean {
        return cacheDir(context).deleteRecursively()
    }

    companion object {
        /// App-private cache dir: needs no storage permission, is never null
        /// (unlike getExternalFilesDir) and can be reclaimed by the system.
        fun cacheDir(context: Context): File {
            val dir = File(context.cacheDir, "pixel_compressor/video")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }
    }
}
