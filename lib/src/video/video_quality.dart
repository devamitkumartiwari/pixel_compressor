// ignore_for_file: constant_identifier_names

enum PixelVideoQuality() {
  DefaultQuality,
  LowQuality,
  MediumQuality,
  HighestQuality,
  Res640x480Quality,
  Res960x540Quality,
  Res1280x720Quality,
  Res1920x1080Quality,
}

/// Output video codec for `compressVideoFile`.
enum PixelVideoCodec() {
  /// H.264 / AVC: plays everywhere. The default.
  h264,

  /// H.265 / HEVC: about 40% smaller at the same quality, but not every
  /// browser or older device can play it. Falls back to H.264 on Android
  /// devices without an HEVC encoder.
  hevc,
}
