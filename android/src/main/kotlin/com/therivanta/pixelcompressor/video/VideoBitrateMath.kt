package com.therivanta.pixelcompressor.video

import com.therivanta.pixelcompressor.QualityPresetWire
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Pure (no Android-runtime-dependent) derivation math for smart-mode video
 * compression and the video target-size iterative loop. Kept dependency
 * free so it's directly unit-testable on the plain JVM.
 */
object VideoBitrateMath {

  const val MIN_BITRATE_BPS = 300_000L
  const val MAX_BITRATE_BPS = 20_000_000L
  const val TARGET_SIZE_MAX_ATTEMPTS = 5
  const val TARGET_SIZE_BITRATE_STEP_FACTOR = 0.65
  const val TARGET_SIZE_RESOLUTION_STEP_FACTOR = 0.75
  const val TARGET_SIZE_MIN_EDGE_PX = 320

  data class Dimensions(val width: Int, val height: Int)

  private data class PresetParams(val longEdge: Int, val bitsPerPixel: Double, val audioBitrateBps: Long)

  private val PRESETS = mapOf(
    QualityPresetWire.VERY_LOW to PresetParams(480, 0.035, 64_000),
    QualityPresetWire.LOW to PresetParams(640, 0.05, 96_000),
    QualityPresetWire.MEDIUM to PresetParams(960, 0.07, 128_000),
    QualityPresetWire.HIGH to PresetParams(1280, 0.10, 160_000),
    QualityPresetWire.VERY_HIGH to PresetParams(1920, 0.14, 192_000),
  )

  private fun paramsFor(preset: QualityPresetWire?): PresetParams =
    PRESETS[preset] ?: PRESETS.getValue(QualityPresetWire.MEDIUM)

  /** Longest-edge resolution default for [preset], never upscaling past
   * the source resolution. Aspect ratio preserved; both dimensions
   * rounded to even numbers (required by most hardware encoders).
   */
  fun deriveResolution(preset: QualityPresetWire?, sourceWidth: Int, sourceHeight: Int): Dimensions {
    if (sourceWidth <= 0 || sourceHeight <= 0) return Dimensions(sourceWidth, sourceHeight)
    val params = paramsFor(preset)
    val sourceLongEdge = max(sourceWidth, sourceHeight)
    val targetLongEdge = min(params.longEdge, sourceLongEdge)
    val scale = targetLongEdge.toDouble() / sourceLongEdge
    return Dimensions(
      roundToEven(sourceWidth * scale),
      roundToEven(sourceHeight * scale),
    )
  }

  /** fps cap by preset, applied only when the caller hasn't set an
   * explicit fps (smart mode, unset field).
   */
  fun deriveFps(preset: QualityPresetWire?, sourceFps: Int): Int {
    if (sourceFps <= 0) return capFor(preset)
    return min(sourceFps, capFor(preset))
  }

  private fun capFor(preset: QualityPresetWire?): Int = when (preset) {
    QualityPresetWire.VERY_LOW, QualityPresetWire.LOW -> 24
    QualityPresetWire.MEDIUM -> 30
    QualityPresetWire.HIGH, QualityPresetWire.VERY_HIGH -> 60
    else -> 30
  }

  /** `bitrateBps = clamp(w*h*fps*bpp, MIN, MAX)`, bpp halved-ish (x0.6)
   * for HEVC vs H.264 at the same preset.
   */
  fun deriveBitrateBps(preset: QualityPresetWire?, width: Int, height: Int, fps: Int, isHevc: Boolean): Long {
    val params = paramsFor(preset)
    val bpp = if (isHevc) params.bitsPerPixel * 0.6 else params.bitsPerPixel
    val raw = width.toDouble() * height.toDouble() * fps.toDouble() * bpp
    return raw.toLong().coerceIn(MIN_BITRATE_BPS, MAX_BITRATE_BPS)
  }

  fun deriveAudioBitrateBps(preset: QualityPresetWire?): Long = paramsFor(preset).audioBitrateBps

  /** Pre-estimates a starting bitrate for the target-size loop from
   * `targetSizeBytes` / duration, reserving ~8% of the bit budget for
   * audio (if enabled) and applying a 0.9 safety factor.
   */
  fun estimateStartingBitrateBps(
    targetSizeBytes: Long,
    durationMs: Long,
    audioEnabled: Boolean,
  ): Long {
    if (durationMs <= 0 || targetSizeBytes <= 0) return MIN_BITRATE_BPS
    val durationSec = durationMs / 1000.0
    val totalBudgetBps = (targetSizeBytes * 8).toDouble() / durationSec
    val audioShare = if (audioEnabled) 0.08 else 0.0
    val videoBudget = totalBudgetBps * (1.0 - audioShare) * 0.9
    return videoBudget.toLong().coerceAtLeast(MIN_BITRATE_BPS)
  }

  /** State stepped down by the target-size loop each failed attempt:
   * bitrate first (to the floor), then resolution (edge length, floored).
   */
  data class AttemptState(val bitrateBps: Long, val maxEdgePx: Int?)

  fun nextAttempt(state: AttemptState, sourceLongEdgePx: Int): AttemptState {
    return if (state.bitrateBps > MIN_BITRATE_BPS) {
      AttemptState(
        bitrateBps = max(MIN_BITRATE_BPS, (state.bitrateBps * TARGET_SIZE_BITRATE_STEP_FACTOR).toLong()),
        maxEdgePx = state.maxEdgePx,
      )
    } else {
      val currentEdge = state.maxEdgePx ?: sourceLongEdgePx
      val newEdge = max(TARGET_SIZE_MIN_EDGE_PX, (currentEdge * TARGET_SIZE_RESOLUTION_STEP_FACTOR).toInt())
      AttemptState(bitrateBps = state.bitrateBps, maxEdgePx = newEdge)
    }
  }

  /** Caps [width]x[height] to fit within [maxWidth]x[maxHeight] (either
   * `null` = unconstrained on that axis), aspect ratio preserved, never
   * upscaling. Both output dimensions rounded to even numbers.
   */
  fun capToBox(width: Int, height: Int, maxWidth: Int?, maxHeight: Int?): Dimensions {
    if (width <= 0 || height <= 0) return Dimensions(width, height)
    if (maxWidth == null && maxHeight == null) return Dimensions(roundToEven(width.toDouble()), roundToEven(height.toDouble()))
    val widthScale = maxWidth?.let { it.toDouble() / width } ?: Double.MAX_VALUE
    val heightScale = maxHeight?.let { it.toDouble() / height } ?: Double.MAX_VALUE
    val scale = min(min(widthScale, heightScale), 1.0)
    return Dimensions(roundToEven(width * scale), roundToEven(height * scale))
  }

  /** Caps [width]x[height] so the longest edge is at most [maxEdgePx],
   * never upscaling. Used by the target-size resolution-stepping loop.
   */
  fun fitLongestEdge(width: Int, height: Int, maxEdgePx: Int): Dimensions =
    capToBox(width, height, maxEdgePx, maxEdgePx)

  private fun roundToEven(value: Double): Int {
    val rounded = value.roundToInt()
    return if (rounded % 2 == 0) max(2, rounded) else max(2, rounded - 1)
  }
}
