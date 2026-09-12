import '../enums/exif_policy.dart';
import '../enums/image_format.dart';

/// Settings for [PixelCompressor.image] compression.
class ImageCompressOptions {
  const ImageCompressOptions({
    this.quality = 80,
    this.maxWidth,
    this.maxHeight,
    this.format,
    this.exifPolicy = ExifPolicy.strip,
    this.rotationDegrees = 0,
    this.targetSizeBytes,
    this.outputPath,
    this.deleteSourceOnSuccess = false,
    this.returnBytes = false,
    this.autoCorrectOrientation = true,
  }) : assert(
         quality >= 1 && quality <= 100,
         'quality must be between 1 and 100',
       ),
       assert(
         rotationDegrees == 0 ||
             rotationDegrees == 90 ||
             rotationDegrees == 180 ||
             rotationDegrees == 270,
         'rotationDegrees must be one of 0, 90, 180, 270',
       ),
       assert(
         targetSizeBytes == null || targetSizeBytes > 0,
         'targetSizeBytes must be positive',
       );

  /// 1-100. Ignored (best-effort) when [targetSizeBytes] is set, since the
  /// native side then searches for a quality that hits the target instead.
  final int quality;

  /// Longest edge is scaled down to fit, aspect ratio preserved. `null`
  /// keeps the source resolution.
  final int? maxWidth;
  final int? maxHeight;

  /// `null` keeps the source's own format.
  final ImageFormat? format;

  final ExifPolicy exifPolicy;

  /// Applied before compression; one of 0/90/180/270.
  final int rotationDegrees;

  /// If set, the native side repeatedly re-encodes at decreasing quality
  /// until the output is at or under this size, or throws
  /// [TargetSizeException] if it can't get there.
  final int? targetSizeBytes;

  /// `null` writes to a cache-managed temp file (see
  /// `PixelCompressor.cache`).
  final String? outputPath;

  /// Deletes the source file after a successful compress. No-op for a
  /// `MediaSource.bytes`/`.asset` input (no real source file), and for an
  /// in-place compress where the output overwrote the source.
  final bool deleteSourceOnSuccess;

  /// Also reads the compressed output back into [CompressionResult.outputBytes].
  /// The output file is still written to disk as normal.
  final bool returnBytes;

  /// When `true` (the default), reads the source's EXIF orientation and
  /// rotates so the output is upright, combined with any requested
  /// [rotationDegrees]. Set `false` to keep the source's raw, uncorrected
  /// pixel orientation.
  final bool autoCorrectOrientation;

  @override
  String toString() =>
      'ImageCompressOptions(quality: $quality, maxWidth: $maxWidth, maxHeight: $maxHeight, '
      'format: $format, exifPolicy: $exifPolicy, targetSizeBytes: $targetSizeBytes)';
}
