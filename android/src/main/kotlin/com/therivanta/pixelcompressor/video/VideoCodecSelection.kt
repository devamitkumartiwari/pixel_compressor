package com.therivanta.pixelcompressor.video

import android.media.MediaFormat
import com.therivanta.pixelcompressor.VideoCodecWire
import com.therivanta.pixelcompressor.capability.CapabilityProbe
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors

/** Resolves a wire [VideoCodecWire] request to a concrete encoder MIME
 * type, honoring the "never silently substitute a codec" contract:
 * [VideoCodecWire.auto] (or unset) prefers HEVC when the device reports
 * hardware support, else H.264; an explicit [VideoCodecWire.hevc] request
 * the device can't satisfy throws `unsupported_codec` before any decode
 * work starts.
 */
object VideoCodecSelection {

  data class Resolved(val mime: String, val wireName: String, val isHevc: Boolean)

  fun resolve(requested: VideoCodecWire?, capabilityProbe: CapabilityProbe): Resolved {
    return when (requested) {
      null, VideoCodecWire.AUTO -> {
        if (capabilityProbe.isHevcSupported()) {
          Resolved(MediaFormat.MIMETYPE_VIDEO_HEVC, "hevc", true)
        } else if (capabilityProbe.isH264Supported()) {
          Resolved(MediaFormat.MIMETYPE_VIDEO_AVC, "h264", false)
        } else {
          throw PixelCompressorErrors.unsupportedCodec(
            "Neither HEVC nor H.264 hardware encoder is available on this device",
          )
        }
      }
      VideoCodecWire.H264 -> {
        if (!capabilityProbe.isH264Supported()) {
          throw PixelCompressorErrors.unsupportedCodec("H.264 encoder is not available on this device")
        }
        Resolved(MediaFormat.MIMETYPE_VIDEO_AVC, "h264", false)
      }
      VideoCodecWire.HEVC -> {
        if (!capabilityProbe.isHevcSupported()) {
          throw PixelCompressorErrors.unsupportedCodec("HEVC encoder is not available on this device")
        }
        Resolved(MediaFormat.MIMETYPE_VIDEO_HEVC, "hevc", true)
      }
    }
  }
}
