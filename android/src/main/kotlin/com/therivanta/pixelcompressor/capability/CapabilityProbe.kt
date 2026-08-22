package com.therivanta.pixelcompressor.capability

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import com.therivanta.pixelcompressor.CapabilitiesReportMessage
import com.therivanta.pixelcompressor.CodecSupportStatusWire

/**
 * Probes on-device encoder support via [MediaCodecList]. WebP encode is
 * always reported supported (`Bitmap.compress(WEBP_LOSSY/LOSSLESS, ...)` is
 * available on every Android API level this plugin targets); HEIC mirrors
 * HEVC support since [androidx.heifwriter.HeifWriter] needs a hardware HEVC
 * encoder under the hood.
 */
class CapabilityProbe {

  private data class EncoderProbe(
    val supported: Boolean,
    val info: MediaCodecInfo?,
  )

  private fun probeEncoder(mime: String): EncoderProbe {
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    val candidates = list.codecInfos.filter { info ->
      info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
    }
    if (candidates.isEmpty()) return EncoderProbe(false, null)

    val preferred = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      candidates.firstOrNull { it.isHardwareAccelerated } ?: candidates.first()
    } else {
      candidates.first()
    }
    return EncoderProbe(true, preferred)
  }

  private fun statusOf(supported: Boolean) =
    if (supported) CodecSupportStatusWire.SUPPORTED else CodecSupportStatusWire.UNSUPPORTED

  fun capabilities(): CapabilitiesReportMessage {
    val h264 = probeEncoder(MediaFormat.MIMETYPE_VIDEO_AVC)
    val hevc = probeEncoder(MediaFormat.MIMETYPE_VIDEO_HEVC)
    val aac = probeEncoder(MediaFormat.MIMETYPE_AUDIO_AAC)

    // Prefer HEVC's hardware capabilities when available (smart-mode video
    // picks HEVC first), else fall back to H.264's.
    val resolutionSource = if (hevc.supported) hevc.info else h264.info
    var maxWidth: Long? = null
    var maxHeight: Long? = null
    try {
      val mime = if (hevc.supported) MediaFormat.MIMETYPE_VIDEO_HEVC else MediaFormat.MIMETYPE_VIDEO_AVC
      val caps = resolutionSource?.getCapabilitiesForType(mime)?.videoCapabilities
      if (caps != null) {
        maxWidth = caps.supportedWidths.upper.toLong()
        maxHeight = caps.supportedHeights.upper.toLong()
      }
    } catch (_: Exception) {
      // Some OEM codecs throw on getCapabilitiesForType for unexpected
      // configurations; a missing max-resolution figure is non-fatal, the
      // rest of the report is still meaningful.
      maxWidth = null
      maxHeight = null
    }

    return CapabilitiesReportMessage(
      h264Encode = statusOf(h264.supported),
      hevcEncode = statusOf(hevc.supported),
      aacEncode = statusOf(aac.supported),
      webpEncode = CodecSupportStatusWire.SUPPORTED,
      heicEncode = statusOf(hevc.supported),
      maxHardwareWidth = maxWidth,
      maxHardwareHeight = maxHeight,
    )
  }

  /** Used by the video engine to decide whether an explicit HEVC request
   * can be honored, and by smart-mode `auto` codec selection.
   */
  fun isHevcSupported(): Boolean = probeEncoder(MediaFormat.MIMETYPE_VIDEO_HEVC).supported

  fun isH264Supported(): Boolean = probeEncoder(MediaFormat.MIMETYPE_VIDEO_AVC).supported

  fun isAacSupported(): Boolean = probeEncoder(MediaFormat.MIMETYPE_AUDIO_AAC).supported
}
