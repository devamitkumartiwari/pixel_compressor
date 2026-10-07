// compressVideo runs on androidx.media3 Transformer.
package com.therivanta.pixelcompressor.video

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.EncoderSelector
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// Handles the `pixel_compressor/video` channel: compression, thumbnails and
/// media info.
@OptIn(markerClass = [UnstableApi::class])
class VideoCompressHandler(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null
    private var pendingDestPath: String? = null
    private var progressPoller: Runnable? = null
    private val channelName = CHANNEL_NAME

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getByteThumbnail" -> {
                val path = call.argument<String>("path")
                val quality = call.argument<Int>("quality")!!
                val position = call.argument<Int>("position")!! // to long
                val maxSize = call.argument<Int>("maxSize") ?: 512
                ThumbnailUtility(channelName).getByteThumbnail(path!!, quality, position.toLong(), maxSize, result)
            }
            "getFileThumbnail" -> {
                val path = call.argument<String>("path")
                val quality = call.argument<Int>("quality")!!
                val position = call.argument<Int>("position")!! // to long
                val maxSize = call.argument<Int>("maxSize") ?: 512
                ThumbnailUtility(channelName).getFileThumbnail(context, path!!, quality,
                        position.toLong(), maxSize, result)
            }
            "getMediaInfo" -> {
                val path = call.argument<String>("path")
                result.success(Utility(channelName).getMediaInfoJson(context, path!!).toString())
            }
            "deleteAllCache" -> {
                result.success(Utility(channelName).deleteAllCache(context))
            }
            "setLogLevel" -> {
                val logLevel = call.argument<Int>("logLevel")!!
                // Transcoder and Media3 share the 0..3 (verbose..error) scale.
                Log.setLogLevel(logLevel)
                result.success(true)
            }
            "cancelCompression" -> {
                val sourcePath = pendingSourcePath
                val destPath = pendingDestPath
                transformer?.cancel()
                destPath?.let { File(it).delete() }
                // Media3 reports no callback for cancel(). Reply like iOS:
                // the source's media info with isCancel = true.
                val reply = sourcePath?.let { source ->
                    runCatching {
                        Utility(channelName).getMediaInfoJson(context, source)
                            .put("isCancel", true)
                            .toString()
                    }.getOrNull()
                }
                finish(reply)
                result.success(false)
            }
            "compressVideo" -> {
                val path = call.argument<String>("path")!!
                val quality = call.argument<Int>("quality")!!
                val deleteOrigin = call.argument<Boolean>("deleteOrigin")!!
                val startTime = call.argument<Int>("startTime")
                val duration = call.argument<Int>("duration")
                val includeAudio = call.argument<Boolean>("includeAudio") ?: true
                val frameRate = call.argument<Int>("frameRate") ?: 30
                val options = CompressOptions(
                    bitrate = call.argument<Int>("bitrate"),
                    maxWidth = call.argument<Int>("maxWidth"),
                    maxHeight = call.argument<Int>("maxHeight"),
                    outputPath = call.argument<String>("outputPath"),
                    hevc = call.argument<String>("codec") == "hevc",
                    keyFrameInterval = call.argument<Double>("keyFrameInterval") ?: 3.0,
                    audioBitrate = call.argument<Int>("audioBitrate"),
                    audioSampleRate = call.argument<Int>("audioSampleRate"),
                    audioChannels = call.argument<Int>("audioChannels"),
                    preventLargerOutput = call.argument<Boolean>("preventLargerOutput") ?: true,
                )

                val destPath: String = options.outputPath?.also {
                    File(it).parentFile?.mkdirs()
                    File(it).delete()
                } ?: run {
                    val tempDir: String = Utility.cacheDir(context).absolutePath
                    val out = SimpleDateFormat("yyyy-MM-dd hh-mm-ss", Locale.US).format(Date())
                    tempDir + File.separator + "VID_" + out + path.hashCode() + ".mp4"
                }

                compressVideo(path, destPath, quality, deleteOrigin, startTime, duration,
                        includeAudio, frameRate, options, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun compressVideo(
        path: String,
        destPath: String,
        quality: Int,
        deleteOrigin: Boolean,
        startTime: Int?,
        duration: Int?,
        includeAudio: Boolean,
        frameRate: Int,
        options: CompressOptions,
        result: MethodChannel.Result,
    ) {
        val source = readSource(path)

        // Same size and bitrate rules as iOS/macOS (VideoTranscoder.swift).
        val videoEffects = mutableListOf<Effect>()
        val target = VideoSizing.targetSize(source.displayWidth, source.displayHeight, quality,
                options.maxWidth, options.maxHeight)
        if (target != null) {
            videoEffects.add(Presentation.createForShortSide(min(target.first, target.second)))
        } else if (source.displayWidth == null && VideoSizing.limits(quality) != null) {
            // Unknown source size: fall back to the preset's short side.
            videoEffects.add(Presentation.createForShortSide(VideoSizing.limits(quality)!!.first))
        }
        // Capped to the input frame rate, like Transcoder's frameRate().
        videoEffects.add(FrameDropEffect.createDefaultFrameDropEffect(frameRate.toFloat()))

        val outWidth = target?.first ?: source.displayWidth
        val outHeight = target?.second ?: source.displayHeight
        val bitrate: Int? = VideoSizing.bitrate(outWidth, outHeight, frameRate, quality,
                options.bitrate, if (options.preventLargerOutput) source.bitrate else null)
        // Keep the original streams if re-encoding would grow the file; only
        // for preset-driven requests (explicit bitrate/size/trim win).
        val allowPassthroughFallback = options.preventLargerOutput && startTime == null &&
                duration == null && options.bitrate == null && options.maxWidth == null &&
                options.maxHeight == null

        // Audio: processors for sample rate / channels; any explicit audio
        // setting forces a re-encode (otherwise an AAC track is copied).
        val audioProcessors = mutableListOf<AudioProcessor>()
        options.audioSampleRate?.let { rate ->
            audioProcessors.add(SonicAudioProcessor().apply { setOutputSampleRateHz(rate) })
        }
        options.audioChannels?.let { channels ->
            audioProcessors.add(ChannelMixingAudioProcessor().apply {
                // Media3 only has default coefficients for mono/stereo inputs.
                for (input in 1..2) {
                    putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(input, channels))
                }
            })
        }
        if (options.audioBitrate != null && audioProcessors.isEmpty()) {
            audioProcessors.add(SonicAudioProcessor()) // no-op; forces re-encode
        }
        val audioBitrate = options.audioBitrate ?: if (options.audioChannels == 1) 64_000 else 128_000

        // startTime / duration are in seconds, matching the iOS implementation.
        val mediaItem = MediaItem.Builder().setUri(Uri.parse(path))
        if (startTime != null || duration != null) {
            val startMs = (startTime ?: 0) * 1000L
            val clipping = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(startMs)
            if (duration != null && duration > 0) {
                clipping.setEndPositionMs(startMs + duration * 1000L)
            }
            mediaItem.setClippingConfiguration(clipping.build())
        }

        val editedMediaItem = EditedMediaItem.Builder(mediaItem.build())
                .setRemoveAudio(!includeAudio || !source.hasAudio)
                .setEffects(Effects(if (source.hasAudio) audioProcessors else emptyList(), videoEffects))
                .build()

        // H.264 output can't carry HDR, so tone-map HDR sources to SDR
        // instead of writing washed-out PQ/HLG pixels as if they were SDR.
        // OpenGL tone-mapping needs API 29; on 28 Media3 falls back itself.
        // Only ask for an audio track the source actually has; otherwise
        // Media3 fills it with generated silence.
        val keepAudio = includeAudio && source.hasAudio
        Log.d(TAG, "compressVideo source=$source quality=$quality target=$target bitrate=$bitrate " +
                "audio=$keepAudio fallback=$allowPassthroughFallback")
        val composition = Composition.Builder(mediaSequence(editedMediaItem, keepAudio))
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                    }
                }
                .build()

        val videoMime = if (options.hevc) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264
        val encoderSettings = VideoEncoderSettings.Builder()
                .setiFrameIntervalSeconds(options.keyFrameInterval.toFloat())
        bitrate?.let {
            encoderSettings.setBitrate(it)
            // Android 12+ raises VBR targets to a "minimum quality" floor
            // (e.g. ~2 Mbps at 720p), which ignores our bitrate and can grow
            // small videos. CBR is exempt; use it when an encoder offers it.
            if (supportsCbr(videoMime)) {
                encoderSettings.setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            }
        }

        val transformer = Transformer.Builder(context)
                // No 400 KB moov reservation; Mp4FastStart moves the index
                // to the front afterwards instead.
                .setMuxerFactory(InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false))
                .setVideoMimeType(videoMime)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(
                        DefaultEncoderFactory.Builder(context)
                                .setVideoEncoderSelector(VIDEO_ENCODER_SELECTOR)
                                .setRequestedVideoEncoderSettings(encoderSettings.build())
                                .setRequestedAudioEncoderSettings(
                                        AudioEncoderSettings.Builder().setBitrate(audioBitrate).build())
                                .setEnableFallback(true)
                                .build()
                )
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        postProcess(path, destPath, includeAudio, allowPassthroughFallback) {
                            completeCompression(path, destPath, deleteOrigin)
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        Log.e(TAG, "compressVideo failed", exportException)
                        File(destPath).delete()
                        finish(null)
                    }
                })
                .build()

        this.transformer = transformer
        this.pendingResult = result
        this.pendingSourcePath = path
        this.pendingDestPath = destPath
        transformer.start(composition, destPath)
        startProgressPolling(transformer)
    }

    private fun mediaSequence(item: EditedMediaItem, includeAudio: Boolean): EditedMediaItemSequence =
        if (includeAudio) {
            EditedMediaItemSequence.withAudioAndVideoFrom(listOf(item))
        } else {
            EditedMediaItemSequence.withVideoFrom(listOf(item))
        }

    /// Extra options after the base compressVideo arguments.
    private data class CompressOptions(
        val bitrate: Int?,
        val maxWidth: Int?,
        val maxHeight: Int?,
        val outputPath: String?,
        val hevc: Boolean = false,
        val keyFrameInterval: Double = 3.0,
        val audioBitrate: Int? = null,
        val audioSampleRate: Int? = null,
        val audioChannels: Int? = null,
        val preventLargerOutput: Boolean = true,
    )

    private fun supportsCbr(mime: String): Boolean = runCatching {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) } &&
                    info.getCapabilitiesForType(mime).encoderCapabilities
                            ?.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR) == true
        }
    }.getOrDefault(false)

    /// Display-oriented source size (rotation applied) and container bitrate.
    private data class SourceInfo(
        val displayWidth: Int?,
        val displayHeight: Int?,
        val bitrate: Int?,
        val hasAudio: Boolean = true,
    )

    private fun readSource(path: String): SourceInfo {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.parse(path))
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            val quarterTurn = rotation == 90 || rotation == 270
            SourceInfo(
                if (quarterTurn) height else width,
                if (quarterTurn) width else height,
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull(),
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
            )
        } catch (e: RuntimeException) {
            SourceInfo(null, null, null)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Ignore failures while cleaning up.
            }
        }
    }

    /// Replies with the output's media info. Never throws (main looper).
    private fun completeCompression(path: String, destPath: String, deleteOrigin: Boolean) {
        channel.invokeMethod("updateProgress", 100.00)
        val json = runCatching { Utility(channelName).getMediaInfoJson(context, destPath) }
                .getOrElse { JSONObject().put("path", destPath) }
        json.put("isCancel", false)
        finish(json.toString())
        if (deleteOrigin) {
            File(path).delete()
        }
    }

    /// Off the main thread: if allowed and the re-encode came out larger than
    /// the source, replace it with the source's own streams (copied with
    /// MediaExtractor → MediaMuxer, no re-encoding); then move the MP4 index
    /// to the front. Calls [done] on the main thread.
    private fun postProcess(
        path: String,
        destPath: String,
        includeAudio: Boolean,
        allowPassthroughFallback: Boolean,
        done: () -> Unit,
    ) {
        Thread {
            val reencoded = File(destPath)
            val sourceSize = File(path).length()
            if (allowPassthroughFallback && sourceSize > 0 && reencoded.length() > sourceSize) {
                val tmp = File("$destPath.remux.mp4")
                try {
                    copyStreams(path, tmp.absolutePath, includeAudio)
                    Log.d(TAG, "passthrough remux: ${tmp.length()} B vs re-encoded ${reencoded.length()} B")
                    if (tmp.length() > sourceSize && (includeAudio || !hasAudioTrack(path)) && isMp4(path)) {
                        // The remuxed container is still slightly larger than
                        // an MP4 source: the source itself is the best output.
                        File(path).copyTo(tmp, overwrite = true)
                    }
                    if (tmp.length() > 0 && tmp.length() < reencoded.length()) {
                        reencoded.delete()
                        if (!tmp.renameTo(reencoded)) {
                            tmp.copyTo(reencoded, overwrite = true)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "passthrough remux failed; keeping re-encoded output", e)
                } finally {
                    tmp.delete()
                }
            }
            runCatching { Mp4FastStart.apply(reencoded) }
                .onFailure { Log.w(TAG, "fast-start failed; output stays playable", it) }
            mainHandler.post(done)
        }.start()
    }

    /// True for ISO-BMFF files with an MP4-family brand (not QuickTime .mov).
    private fun isMp4(path: String): Boolean = runCatching {
        val header = ByteArray(12)
        java.io.FileInputStream(path).use { if (it.read(header) < 12) return false }
        val type = String(header, 4, 4, Charsets.US_ASCII)
        val brand = String(header, 8, 4, Charsets.US_ASCII)
        type == "ftyp" && brand != "qt  "
    }.getOrDefault(false)

    private fun hasAudioTrack(path: String): Boolean {
        val extractor = android.media.MediaExtractor()
        return try {
            extractor.setDataSource(path)
            (0 until extractor.trackCount).any {
                extractor.getTrackFormat(it).getString(android.media.MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
        } catch (e: Exception) {
            true
        } finally {
            extractor.release()
        }
    }

    private fun copyStreams(src: String, dst: String, includeAudio: Boolean) {
        val extractor = android.media.MediaExtractor()
        var muxer: android.media.MediaMuxer? = null
        try {
            extractor.setDataSource(src)
            muxer = android.media.MediaMuxer(dst, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = HashMap<Int, Int>()
            var maxInput = 1 shl 20
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                val isVideo = mime.startsWith("video/")
                if (!isVideo && !(includeAudio && mime.startsWith("audio/"))) continue
                if (isVideo && format.containsKey(android.media.MediaFormat.KEY_ROTATION)) {
                    muxer.setOrientationHint(format.getInteger(android.media.MediaFormat.KEY_ROTATION))
                }
                if (format.containsKey(android.media.MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxInput = max(maxInput, format.getInteger(android.media.MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                trackMap[i] = muxer.addTrack(format)
                extractor.selectTrack(i)
            }
            if (trackMap.isEmpty()) throw IllegalStateException("no tracks to copy")
            muxer.start()
            val buffer = java.nio.ByteBuffer.allocate(maxInput)
            val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val target = trackMap[extractor.sampleTrackIndex]
                if (target != null) {
                    // Extractor and codec flags use different values; map them.
                    val sampleFlags = extractor.sampleFlags
                    var flags = 0
                    if (sampleFlags and android.media.MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                        flags = flags or android.media.MediaCodec.BUFFER_FLAG_KEY_FRAME
                    }
                    if (sampleFlags and android.media.MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME != 0) {
                        flags = flags or android.media.MediaCodec.BUFFER_FLAG_PARTIAL_FRAME
                    }
                    info.set(0, size, extractor.sampleTime, flags)
                    muxer.writeSampleData(target, buffer, info)
                }
                extractor.advance()
            }
            muxer.stop()
        } finally {
            try { muxer?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    private fun startProgressPolling(transformer: Transformer) {
        val holder = ProgressHolder()
        val poller = object : Runnable {
            override fun run() {
                if (this@VideoCompressHandler.transformer !== transformer) return
                if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("updateProgress", holder.progress.toDouble())
                }
                mainHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
            }
        }
        progressPoller = poller
        mainHandler.post(poller)
    }

    private fun finish(reply: String?) {
        progressPoller?.let { mainHandler.removeCallbacks(it) }
        progressPoller = null
        transformer = null
        pendingSourcePath = null
        pendingDestPath = null
        val result = pendingResult ?: return
        pendingResult = null
        result.success(reply)
    }

    fun dispose() {
        transformer?.cancel()
        progressPoller?.let { mainHandler.removeCallbacks(it) }
        progressPoller = null
        transformer = null
        pendingResult = null
        pendingSourcePath = null
        pendingDestPath = null
    }

    companion object {
        /// Android 9 ships the Codec2 software encoders (c2.android.*) as an
        /// experimental path that fails with surface input; prefer anything
        /// else there (hardware or OMX.google.*). Newer releases: default order.
        private val VIDEO_ENCODER_SELECTOR = EncoderSelector { mimeType ->
            val all = EncoderSelector.DEFAULT.selectEncoderInfos(mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return@EncoderSelector all
            val preferred = all.filterNot { it.name.startsWith("c2.android.") }
            com.google.common.collect.ImmutableList.copyOf(preferred.ifEmpty { all })
        }

        const val CHANNEL_NAME = "pixel_compressor/video"
        private const val TAG = "PixelVideoCompress"
        private const val PROGRESS_INTERVAL_MS = 100L
    }
}

/// Output size and bitrate rules shared with iOS/macOS (VideoTranscoder.swift).
internal object VideoSizing {
    /// Share of the source bitrate the output may use (hardware encoders overshoot).
    private const val SOURCE_BITRATE_FACTOR = 0.75

    /// (max short side, max long side) per PixelVideoQuality index; null = keep source size.
    fun limits(quality: Int): Pair<Int, Int>? = when (quality) {
        0 -> 720 to Int.MAX_VALUE
        1 -> 360 to Int.MAX_VALUE
        2 -> 640 to Int.MAX_VALUE
        3 -> null
        4 -> 480 to 640
        5 -> 540 to 960
        6 -> 720 to 1280
        7 -> 1080 to 1920
        else -> 340 to Int.MAX_VALUE
    }

    /// Display-oriented output (width, height), scaled down (never up) to the
    /// quality limits and the optional max box, even-rounded. Null when the
    /// source size is unknown or no scaling is needed.
    fun targetSize(width: Int?, height: Int?, quality: Int, maxWidth: Int?, maxHeight: Int?): Pair<Int, Int>? {
        if (width == null || height == null || width <= 0 || height <= 0) return null
        var scale = 1.0
        limits(quality)?.let { (short, long) ->
            scale = minOf(scale, short.toDouble() / minOf(width, height), long.toDouble() / maxOf(width, height))
        }
        if (maxWidth != null && maxWidth > 0) scale = minOf(scale, maxWidth.toDouble() / width)
        if (maxHeight != null && maxHeight > 0) scale = minOf(scale, maxHeight.toDouble() / height)
        if (scale >= 1.0) return null
        fun even(v: Double) = maxOf(2, (v / 2).toInt() * 2)
        return even(width * scale) to even(height * scale)
    }

    /// Requested bitrate, else a size-based estimate capped below the source's.
    fun bitrate(width: Int?, height: Int?, fps: Int, quality: Int, requested: Int?, sourceBitrate: Int?): Int? {
        if (requested != null && requested > 0) return requested
        if (width == null || height == null) return null
        val divisor = if (quality == 3) 5.0 else 10.0
        var estimate = width.toDouble() * height * fps / divisor
        if (sourceBitrate != null && sourceBitrate > 0) {
            estimate = minOf(estimate, sourceBitrate * SOURCE_BITRATE_FACTOR)
        }
        return maxOf(estimate.toInt(), 100_000)
    }
}
