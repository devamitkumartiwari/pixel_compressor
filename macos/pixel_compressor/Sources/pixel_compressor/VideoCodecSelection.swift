import AVFoundation
import Foundation

/// Codec resolution and smart/manual-mode resolution/fps/bitrate
/// derivation for `VideoEngine`. Pure math/AVFoundation-constant lookups —
/// no I/O — so it's trivially unit-testable and safe to copy byte-for-byte
/// to macOS.
enum VideoCodecSelection {
  struct DerivedSettings {
    let width: Int
    let height: Int
    let fps: Int
    let bitrateBps: Int
    let audioBitrateBps: Int
  }

  static let bppByPreset: [QualityPresetWire: Double] = [
    .veryLow: 0.035,
    .low: 0.05,
    .medium: 0.07,
    .high: 0.10,
    .veryHigh: 0.14,
  ]

  static let longestEdgeByPreset: [QualityPresetWire: Int] = [
    .veryLow: 480,
    .low: 640,
    .medium: 960,
    .high: 1280,
    .veryHigh: 1920,
  ]

  static let audioBitrateByPreset: [QualityPresetWire: Int] = [
    .veryLow: 64_000,
    .low: 96_000,
    .medium: 128_000,
    .high: 160_000,
    .veryHigh: 192_000,
  ]

  static let minBitrateBps = 300_000
  static let maxBitrateBps = 20_000_000

  /// Resolves the wire codec request to a concrete `AVVideoCodecType`.
  /// Explicit `.hevc` requests that the device can't satisfy throw
  /// `unsupported_codec` immediately — never silently substituted.
  /// `.auto` (and `nil`) prefers HEVC when supported, else H.264.
  static func resolveCodecType(requested: VideoCodecWire?, hevcSupported: Bool) throws -> (
    type: AVVideoCodecType, isHevc: Bool
  ) {
    switch requested ?? .auto {
    case .h264:
      return (.h264, false)
    case .hevc:
      guard hevcSupported else {
        throw PixelCompressorError.unsupportedCodec(
          "HEVC hardware encoder isn't available on this device")
      }
      return (.hevc, true)
    case .auto:
      return hevcSupported ? (.hevc, true) : (.h264, false)
    }
  }

  static func fpsCap(for preset: QualityPresetWire, sourceFps: Double) -> Int {
    let capped: Double
    switch preset {
    case .veryLow, .low: capped = min(sourceFps, 24)
    case .medium: capped = min(sourceFps, 30)
    case .high, .veryHigh: capped = min(sourceFps, 60)
    case .custom: capped = sourceFps
    }
    return max(1, Int(capped.rounded()))
  }

  static func clampBitrate(_ bitrateBps: Double) -> Int {
    Int(min(max(bitrateBps, Double(minBitrateBps)), Double(maxBitrateBps)))
  }

  static func evenify(_ value: Int) -> Int {
    max(2, value % 2 == 0 ? value : value - 1)
  }

  /// Scales `(sourceWidth, sourceHeight)` down so its longest edge is at
  /// most `targetLongestEdge`, never upscaling, preserving aspect ratio,
  /// and rounding both dimensions to even numbers (required by most
  /// hardware encoders).
  static func scaledSize(sourceWidth: Int, sourceHeight: Int, targetLongestEdge: Int) -> (
    width: Int, height: Int
  ) {
    let sourceLongestEdge = max(sourceWidth, sourceHeight)
    guard sourceLongestEdge > 0, targetLongestEdge < sourceLongestEdge else {
      return (evenify(sourceWidth), evenify(sourceHeight))
    }
    let scale = Double(targetLongestEdge) / Double(sourceLongestEdge)
    let width = evenify(max(2, Int((Double(sourceWidth) * scale).rounded())))
    let height = evenify(max(2, Int((Double(sourceHeight) * scale).rounded())))
    return (width, height)
  }

  /// `CompressionMode.smart`: resolution/fps/bitrate/audio-bitrate are all
  /// derived from `preset`, capped by any explicit `maxWidth`/`maxHeight`/
  /// `fps` the caller also supplied, and never upscaled past the source.
  static func smartSettings(
    preset: QualityPresetWire,
    sourceWidth: Int,
    sourceHeight: Int,
    sourceFps: Double,
    requestedMaxWidth: Int?,
    requestedMaxHeight: Int?,
    requestedFps: Int?,
    isHevc: Bool
  ) -> DerivedSettings {
    let sourceLongestEdge = max(sourceWidth, sourceHeight)
    var targetLongestEdge = min(longestEdgeByPreset[preset] ?? sourceLongestEdge, sourceLongestEdge)
    if let maxW = requestedMaxWidth, let maxH = requestedMaxHeight {
      targetLongestEdge = min(targetLongestEdge, max(maxW, maxH))
    } else if let maxW = requestedMaxWidth {
      targetLongestEdge = min(targetLongestEdge, maxW)
    } else if let maxH = requestedMaxHeight {
      targetLongestEdge = min(targetLongestEdge, maxH)
    }

    let (width, height) = scaledSize(
      sourceWidth: sourceWidth, sourceHeight: sourceHeight, targetLongestEdge: targetLongestEdge)
    let fps = requestedFps ?? fpsCap(for: preset, sourceFps: sourceFps)

    let bpp = (bppByPreset[preset] ?? 0.07) * (isHevc ? 0.6 : 1.0)
    let bitrateBps = clampBitrate(Double(width) * Double(height) * Double(fps) * bpp)
    let audioBitrateBps = audioBitrateByPreset[preset] ?? 128_000

    return DerivedSettings(
      width: width, height: height, fps: fps, bitrateBps: bitrateBps,
      audioBitrateBps: audioBitrateBps)
  }

  /// `CompressionMode.manual`: request values are used as given; any unset
  /// field falls back to the source value (resolution/fps) or the
  /// `medium`-preset derived value (bitrate/audio bitrate) — no
  /// preset-driven resolution/fps substitution, since that's smart-mode-only
  /// behavior.
  static func manualSettings(
    sourceWidth: Int,
    sourceHeight: Int,
    sourceFps: Double,
    requestedMaxWidth: Int?,
    requestedMaxHeight: Int?,
    requestedFps: Int?,
    requestedBitrateBps: Int?,
    requestedAudioBitrateBps: Int?,
    isHevc: Bool
  ) -> DerivedSettings {
    var width = sourceWidth
    var height = sourceHeight
    if requestedMaxWidth != nil || requestedMaxHeight != nil {
      var scale = 1.0
      if let maxW = requestedMaxWidth, sourceWidth > maxW {
        scale = min(scale, Double(maxW) / Double(sourceWidth))
      }
      if let maxH = requestedMaxHeight, sourceHeight > maxH {
        scale = min(scale, Double(maxH) / Double(sourceHeight))
      }
      if scale < 1.0 {
        width = Int((Double(sourceWidth) * scale).rounded())
        height = Int((Double(sourceHeight) * scale).rounded())
      }
    }
    width = evenify(width)
    height = evenify(height)

    let fps = requestedFps ?? max(1, Int(sourceFps.rounded()))

    let mediumBpp = (bppByPreset[.medium] ?? 0.07) * (isHevc ? 0.6 : 1.0)
    let mediumBitrate = clampBitrate(Double(width) * Double(height) * Double(fps) * mediumBpp)
    let bitrateBps = requestedBitrateBps ?? mediumBitrate
    let audioBitrateBps = requestedAudioBitrateBps ?? (audioBitrateByPreset[.medium] ?? 128_000)

    return DerivedSettings(
      width: width, height: height, fps: fps, bitrateBps: bitrateBps,
      audioBitrateBps: audioBitrateBps)
  }
}
