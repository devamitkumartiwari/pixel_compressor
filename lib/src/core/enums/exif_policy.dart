/// What to do with EXIF metadata during image compression.
enum ExifPolicy {
  /// Keep EXIF data, with orientation normalized to "upright" if a
  /// rotation was applied (so the image never double-rotates in viewers
  /// that respect the EXIF orientation tag).
  keep,

  /// Strip all EXIF data from the output — the default, since EXIF can
  /// carry GPS coordinates and other data callers don't always intend to
  /// share.
  strip,
}
