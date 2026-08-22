package com.therivanta.pixelcompressor.video

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Audio-track transcode pipeline: `MediaExtractor` -> `MediaCodec` decoder
 * (to PCM) -> `MediaCodec` AAC encoder. Sample rate and channel count are
 * kept from the source (no resampling/downmixing); only the bitrate
 * changes, per [VideoBitrateMath.deriveAudioBitrateBps] /
 * `request.audioBitrateBps`.
 */
internal class AudioTranscoder {

  data class Result(val format: MediaFormat, val samples: List<EncodedSample>)

  companion object {
    private const val TIMEOUT_US = 10_000L
  }

  suspend fun transcode(
    sourcePath: String,
    audioTrackIndex: Int,
    sourceFormat: MediaFormat,
    bitrateBps: Long,
    trimStartUs: Long,
    trimEndUs: Long?,
  ): Result {
    val extractor = MediaExtractor()
    var decoder: MediaCodec? = null
    var encoder: MediaCodec? = null

    try {
      extractor.setDataSource(sourcePath)
      extractor.selectTrack(audioTrackIndex)
      if (trimStartUs > 0) {
        extractor.seekTo(trimStartUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
      }

      val sourceMime = sourceFormat.getString(MediaFormat.KEY_MIME)
        ?: throw PixelCompressorErrors.decodingError("Source audio track has no MIME type")
      val sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
      val channelCount = sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

      decoder = try {
        MediaCodec.createDecoderByType(sourceMime).also {
          it.configure(sourceFormat, null, null, 0)
        }
      } catch (e: Exception) {
        throw PixelCompressorErrors.decodingError(
          "Audio decoder for $sourceMime could not be configured: ${e.message}",
          e.toString(),
        )
      }

      val encFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
        setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps.toInt())
        setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
      }
      encoder = try {
        MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also {
          it.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
      } catch (e: Exception) {
        throw PixelCompressorErrors.unsupportedCodec(
          "AAC encoder could not be configured: ${e.message}",
          e.toString(),
        )
      }

      decoder.start()
      encoder.start()

      var extractorDone = false
      var decoderDone = false
      var encoderDone = false
      val decoderInfo = MediaCodec.BufferInfo()
      val encoderInfo = MediaCodec.BufferInfo()
      val samples = mutableListOf<EncodedSample>()
      var outputFormat: MediaFormat? = null

      while (!encoderDone) {
        currentCoroutineContext().ensureActive()

        if (!extractorDone) {
          val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
          if (inputIndex >= 0) {
            val inputBuffer = decoder.getInputBuffer(inputIndex)
              ?: throw PixelCompressorErrors.decodingError("Audio decoder returned a null input buffer")
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
          val decoderStatus = decoder.dequeueOutputBuffer(decoderInfo, TIMEOUT_US)
          if (decoderStatus >= 0) {
            val isEos = (decoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
            if (decoderInfo.size > 0) {
              val decodedBuffer = decoder.getOutputBuffer(decoderStatus)
                ?: throw PixelCompressorErrors.decodingError("Audio decoder returned a null output buffer")
              decodedBuffer.position(decoderInfo.offset)
              decodedBuffer.limit(decoderInfo.offset + decoderInfo.size)

              val encInputIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
              if (encInputIndex >= 0) {
                val encInputBuffer = encoder.getInputBuffer(encInputIndex)
                  ?: throw PixelCompressorErrors.encodingError("Audio encoder returned a null input buffer")
                encInputBuffer.clear()
                encInputBuffer.put(decodedBuffer)
                encoder.queueInputBuffer(
                  encInputIndex,
                  0,
                  decoderInfo.size,
                  (decoderInfo.presentationTimeUs - trimStartUs).coerceAtLeast(0),
                  if (isEos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                )
              }
            } else if (isEos) {
              val encInputIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
              if (encInputIndex >= 0) {
                encoder.queueInputBuffer(encInputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              }
            }
            decoder.releaseOutputBuffer(decoderStatus, false)
            if (isEos) decoderDone = true
          }
        }

        var draining = true
        while (draining) {
          when (val encoderStatus = encoder.dequeueOutputBuffer(encoderInfo, 0)) {
            MediaCodec.INFO_TRY_AGAIN_LATER -> draining = false
            MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> outputFormat = encoder.outputFormat
            else -> if (encoderStatus >= 0) {
              val isConfig = (encoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
              if (!isConfig && encoderInfo.size > 0) {
                val encodedData = encoder.getOutputBuffer(encoderStatus)
                  ?: throw PixelCompressorErrors.encodingError("Audio encoder returned a null output buffer")
                encodedData.position(encoderInfo.offset)
                encodedData.limit(encoderInfo.offset + encoderInfo.size)
                val bytes = ByteArray(encoderInfo.size)
                encodedData.get(bytes)
                samples.add(EncodedSample(bytes, encoderInfo.presentationTimeUs, encoderInfo.flags))
              }
              encoder.releaseOutputBuffer(encoderStatus, false)
              if ((encoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
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
        ?: throw PixelCompressorErrors.encodingError("Audio encoder never reported an output format")
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
      extractor.release()
    }
  }
}
