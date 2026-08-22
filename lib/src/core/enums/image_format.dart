/// Output image formats. Not every format is supported on every platform —
/// check [PixelCompressor.capabilities] before relying on WebP or HEIC.
enum ImageFormat {
  /// Lossy, universally supported. The default when no format is given —
  /// the source's own format is kept instead.
  jpeg,

  /// Lossless, supports transparency.
  png,

  /// Lossy or lossless, smaller than JPEG at equal quality. Android only —
  /// iOS/macOS's ImageIO can decode WebP but cannot encode it.
  webp,

  /// Apple's preferred modern format. Android support requires a
  /// hardware HEVC encoder; unsupported devices fall back with a clear
  /// [UnsupportedCodecException].
  heic,
}
