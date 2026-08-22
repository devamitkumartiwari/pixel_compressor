/// Output video codec.
enum VideoCodec {
  /// Universally supported, larger output than HEVC at equal quality.
  h264,

  /// ~30-50% smaller than H.264 at equal quality, but needs a hardware HEVC
  /// encoder — check [PixelCompressor.capabilities] first, or use
  /// [VideoCodec.auto] to let the native side fall back automatically.
  hevc,

  /// Prefer HEVC when the device has a hardware encoder for it, otherwise
  /// fall back to H.264. Recommended default.
  auto,
}
