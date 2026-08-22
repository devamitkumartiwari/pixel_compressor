/// A named quality/bitrate tradeoff for [CompressionMode.smart] video
/// compression — the native side picks concrete encoder settings for you.
enum QualityPreset {
  /// Smallest file, most visible quality loss.
  veryLow,

  low,

  /// Good default for sharing over messaging apps.
  medium,

  high,

  /// Largest file of the presets, closest to source quality.
  veryHigh,

  /// Ignore the preset and use the explicit `bitrateBps`/`codec`/etc values
  /// instead. Only meaningful with [CompressionMode.manual].
  custom,
}
