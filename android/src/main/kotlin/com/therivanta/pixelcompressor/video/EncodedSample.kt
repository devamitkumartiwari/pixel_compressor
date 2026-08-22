package com.therivanta.pixelcompressor.video

/** One encoded access unit, PTS already adjusted relative to the trim
 * window's start (so muxed output always starts at PTS 0).
 */
internal data class EncodedSample(
  val data: ByteArray,
  val presentationTimeUs: Long,
  val flags: Int,
)
