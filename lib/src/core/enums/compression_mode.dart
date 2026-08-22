/// How a [VideoCompressOptions] request picks its encoder settings.
enum CompressionMode {
  /// You supply `codec`, `bitrateBps`, `fps`, etc. directly.
  manual,

  /// You supply a [QualityPreset] (and optionally a target size) and the
  /// native side derives resolution/bitrate/codec for you.
  smart,
}
