package com.therivanta.pixelcompressor.video

import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Video-track transcode pipeline: `MediaExtractor` (compressed source
 * samples) -> `MediaCodec` decoder (writing to a `SurfaceTexture`) -> GPU
 * scale + rotate (via `glViewport` and a position-matrix rotation, see
 * [GlUtil]) -> `MediaCodec` encoder (reading from its own input `Surface`).
 * Trim is applied by seeking the extractor to `trimStartUs` and
 * dropping/rewriting sample PTS. Rotation is baked directly into the
 * encoded pixels here (rather than left as a `MediaMuxer` orientation
 * hint) because many server-side players/transcoders ignore that hint —
 * [targetWidth]/[targetHeight] must already be the caller's post-rotation
 * (swapped, for 90/270) dimensions; see [VideoEngine].
 *
 * Encoded samples are buffered in memory rather than streamed straight to
 * the muxer, because the muxer can't have tracks added (and therefore
 * can't be started) until *both* the video and audio encoders have each
 * emitted their `INFO_OUTPUT_FORMAT_CHANGED` output format — so
 * [VideoEngine] runs this pass and [AudioTranscoder]'s pass to completion
 * first, then muxes both buffered sample lists together.
 */
internal class VideoTranscoder {

  data class Result(val format: MediaFormat, val samples: List<EncodedSample>)

  private class FrameAvailableWaiter {
    private val lock = Object()
    private var available = false

    fun listener(): SurfaceTexture.OnFrameAvailableListener =
      SurfaceTexture.OnFrameAvailableListener {
        synchronized(lock) {
          available = true
          lock.notifyAll()
        }
      }

    fun await() {
      synchronized(lock) {
        var waitedMs = 0L
        while (!available && waitedMs < FRAME_WAIT_TIMEOUT_MS) {
          lock.wait(50)
          waitedMs += 50
        }
        available = false
      }
    }
  }

  companion object {
    private const val TIMEOUT_US = 10_000L
    private const val FRAME_WAIT_TIMEOUT_MS = 2_500L
    private const val I_FRAME_INTERVAL_SECONDS = 2
  }

  suspend fun transcode(
    sourcePath: String,
    videoTrackIndex: Int,
    sourceFormat: MediaFormat,
    outputMime: String,
    targetWidth: Int,
    targetHeight: Int,
    targetFps: Int,
    bitrateBps: Long,
    trimStartUs: Long,
    trimEndUs: Long?,
    rotationDegrees: Int,
    onProgress: (currentPtsUs: Long) -> Unit,
  ): Result {
    val extractor = MediaExtractor()
    var decoder: MediaCodec? = null
    var encoder: MediaCodec? = null
    var eglCore: EglCore? = null
    var windowSurface: WindowSurface? = null
    var decoderOutputSurface: Surface? = null
    var surfaceTexture: SurfaceTexture? = null

    try {
      extractor.setDataSource(sourcePath)
      extractor.selectTrack(videoTrackIndex)
      if (trimStartUs > 0) {
        extractor.seekTo(trimStartUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
      }

      val sourceMime = sourceFormat.getString(MediaFormat.KEY_MIME)
        ?: throw PixelCompressorErrors.decodingError("Source video track has no MIME type")

      val encFormat = MediaFormat.createVideoFormat(outputMime, targetWidth, targetHeight).apply {
        setInteger(MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps.toInt())
        setInteger(MediaFormat.KEY_FRAME_RATE, targetFps.coerceAtLeast(1))
        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SECONDS)
      }

      encoder = try {
        MediaCodec.createEncoderByType(outputMime).also {
          it.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
      } catch (e: Exception) {
        throw PixelCompressorErrors.unsupportedCodec(
          "Encoder for $outputMime could not be configured: ${e.message}",
          e.toString(),
        )
      }
      val encoderInputSurface = encoder.createInputSurface()

      eglCore = EglCore()
      windowSurface = WindowSurface(eglCore, encoderInputSurface)
      windowSurface.makeCurrent()
      val renderer = TextureRenderer()

      val frameWaiter = FrameAvailableWaiter()
      surfaceTexture = SurfaceTexture(renderer.externalTextureId)
      surfaceTexture.setOnFrameAvailableListener(frameWaiter.listener(), Handler(Looper.getMainLooper()))
      decoderOutputSurface = Surface(surfaceTexture)

      decoder = try {
        MediaCodec.createDecoderByType(sourceMime).also {
          it.configure(sourceFormat, decoderOutputSurface, null, 0)
        }
      } catch (e: Exception) {
        throw PixelCompressorErrors.decodingError(
          "Decoder for $sourceMime could not be configured: ${e.message}",
          e.toString(),
        )
      }

      decoder.start()
      encoder.start()

      var extractorDone = false
      var decoderDone = false
      var encoderDone = false
      val bufferInfo = MediaCodec.BufferInfo()
      val samples = mutableListOf<EncodedSample>()
      var outputFormat: MediaFormat? = null

      while (!encoderDone) {
        currentCoroutineContext().ensureActive()

        if (!extractorDone) {
          val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
          if (inputIndex >= 0) {
            val inputBuffer = decoder.getInputBuffer(inputIndex)
              ?: throw PixelCompressorErrors.decodingError("Decoder returned a null input buffer")
            val sampleSize = extractor.readSampleData(inputBuffer, 0)
            val sampleTimeUs = extractor.sampleTime
            if (sampleSize < 0 || (trimEndUs != null && sampleTimeUs > trimEndUs)) {
              decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              extractorDone = true
            } else {
              decoder.queueInputBuffer(inputIndex, 0, sampleSize, sampleTimeUs, 0)
              extractor.advance()
            }
          }
        }

        if (!decoderDone) {
          when (val decoderStatus = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)) {
            MediaCodec.INFO_TRY_AGAIN_LATER, MediaCodec.INFO_OUTPUT_FORMAT_CHANGED,
            MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED,
            -> Unit
            else -> if (decoderStatus >= 0) {
              val doRender = bufferInfo.size != 0
              val isEos = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
              decoder.releaseOutputBuffer(decoderStatus, doRender)
              if (doRender) {
                frameWaiter.await()
                surfaceTexture.updateTexImage()
                renderer.drawFrame(surfaceTexture, targetWidth, targetHeight, rotationDegrees)
                windowSurface.setPresentationTime(bufferInfo.presentationTimeUs * 1000)
                windowSurface.swapBuffers()
                onProgress(bufferInfo.presentationTimeUs)
              }
              if (isEos) {
                decoderDone = true
                encoder.signalEndOfInputStream()
              }
            }
          }
        }

        var draining = true
        while (draining) {
          when (val encoderStatus = encoder.dequeueOutputBuffer(bufferInfo, 0)) {
            MediaCodec.INFO_TRY_AGAIN_LATER -> draining = false
            MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> outputFormat = encoder.outputFormat
            else -> if (encoderStatus >= 0) {
              val isConfig = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
              if (!isConfig && bufferInfo.size > 0) {
                val encodedData = encoder.getOutputBuffer(encoderStatus)
                  ?: throw PixelCompressorErrors.encodingError("Encoder returned a null output buffer")
                encodedData.position(bufferInfo.offset)
                encodedData.limit(bufferInfo.offset + bufferInfo.size)
                val bytes = ByteArray(bufferInfo.size)
                encodedData.get(bytes)
                samples.add(
                  EncodedSample(
                    data = bytes,
                    presentationTimeUs = (bufferInfo.presentationTimeUs - trimStartUs).coerceAtLeast(0),
                    flags = bufferInfo.flags,
                  ),
                )
              }
              encoder.releaseOutputBuffer(encoderStatus, false)
              if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                encoderDone = true
                draining = false
              }
            } else {
              draining = false
            }
          }
        }
      }

      val finalFormat = outputFormat
        ?: throw PixelCompressorErrors.encodingError("Video encoder never reported an output format")
      return Result(finalFormat, samples)
    } finally {
      try {
        decoder?.stop()
      } catch (_: Exception) {
      }
      decoder?.release()
      try {
        encoder?.stop()
      } catch (_: Exception) {
      }
      encoder?.release()
      surfaceTexture?.release()
      decoderOutputSurface?.release()
      windowSurface?.release()
      eglCore?.release()
      extractor.release()
    }
  }
}
