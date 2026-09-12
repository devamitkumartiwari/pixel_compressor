import '../enums/compression_mode.dart';
import '../enums/quality_preset.dart';
import '../enums/video_codec.dart';

/// Settings for [PixelCompressor.video] compression.
///
/// In [CompressionMode.smart] (the default), set [preset] and let the
/// native side derive resolution/bitrate/codec. In [CompressionMode.manual],
/// set [codec]/[bitrateBps]/[fps]/etc. directly instead.
class VideoCompressOptions {
  const VideoCompressOptions({
    this.mode = CompressionMode.smart,
    this.preset = QualityPreset.medium,
    this.codec,
    this.maxWidth,
    this.maxHeight,
    this.fps,
    this.bitrateBps,
    this.audioEnabled = true,
    this.audioBitrateBps,
    this.trimStart,
    this.trimEnd,
    this.rotationDegrees = 0,
    this.targetSizeBytes,
    this.outputPath,
    this.deleteSourceOnSuccess = false,
    this.returnBytes = false,
  }) : assert(
         rotationDegrees == 0 ||
             rotationDegrees == 90 ||
             rotationDegrees == 180 ||
             rotationDegrees == 270,
         'rotationDegrees must be one of 0, 90, 180, 270',
       ),
       assert(
         targetSizeBytes == null || targetSizeBytes > 0,
         'targetSizeBytes must be positive',
       ),
       assert(
         bitrateBps == null || bitrateBps > 0,
         'bitrateBps must be positive',
       ),
       assert(fps == null || fps > 0, 'fps must be positive');

  final CompressionMode mode;

  /// Used in [CompressionMode.smart]; ignored in manual mode.
  final QualityPreset? preset;

  /// `null`/[VideoCodec.auto] picks HEVC when a hardware encoder is
  /// available, otherwise H.264.
  final VideoCodec? codec;

  /// Longest edge is scaled down to fit, aspect ratio preserved.
  final int? maxWidth;
  final int? maxHeight;

  final int? fps;

  /// Manual mode only.
  final int? bitrateBps;

  final bool audioEnabled;

  /// Manual mode only; ignored if [audioEnabled] is false.
  final int? audioBitrateBps;

  /// Trims the source to `[trimStart, trimEnd]` before compressing. Both
  /// `null` keeps the full duration.
  final Duration? trimStart;
  final Duration? trimEnd;

  /// Applied before compression; one of 0/90/180/270.
  final int rotationDegrees;

  /// If set, the native side steps down resolution/bitrate until the
  /// output is at or under this size, or throws [TargetSizeException] if
  /// it can't get there.
  final int? targetSizeBytes;

  /// `null` writes to a cache-managed temp file (see
  /// `PixelCompressor.cache`).
  final String? outputPath;

  /// Deletes the source file after a successful compress. No-op for a
  /// `MediaSource.bytes`/`.asset` input (no real source file), and for an
  /// in-place compress where the output overwrote the source.
  final bool deleteSourceOnSuccess;

  /// Also reads the compressed output back into [CompressionResult.outputBytes].
  /// The output file is still written to disk as normal. The whole file is
  /// loaded into memory at once — avoid this for very large outputs.
  final bool returnBytes;

  @override
  String toString() =>
      'VideoCompressOptions(mode: $mode, preset: $preset, codec: $codec, '
      'maxWidth: $maxWidth, maxHeight: $maxHeight, targetSizeBytes: $targetSizeBytes)';
}
