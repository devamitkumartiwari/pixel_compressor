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

  @override
  String toString() =>
      'ImageCompressOptions(quality: $quality, maxWidth: $maxWidth, maxHeight: $maxHeight, '
      'format: $format, exifPolicy: $exifPolicy, targetSizeBytes: $targetSizeBytes)';
}
