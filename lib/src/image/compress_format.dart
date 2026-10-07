/// Output format for image compression.
enum PixelImageFormat() {
  jpeg,
  png,

  /// HEIC / HEIF.
  /// - iOS and macOS: always available.
  /// - Android: API 28+ on a device with a hardware HEIF encoder (written
  ///   with AndroidX HeifWriter). Without one, compression throws a
  ///   `PixelCompressError` with code `unsupported_format`.
  heic,

  /// WebP. Not available on macOS, which has no WebP encoder.
  webp,
}
