import '../enums/image_format.dart';

/// Settings for [PixelCompressor.thumbnails] generation.
class ThumbnailOptions {
  const ThumbnailOptions({
    required this.positions,
    this.maxWidth = 320,
    this.maxHeight = 320,
    this.format = ImageFormat.jpeg,
    this.quality = 80,
  }) : assert(
         quality >= 1 && quality <= 100,
         'quality must be between 1 and 100',
       );

  /// Timestamps in the source video to capture a frame at. Validated
  /// against the source's real duration (via a metadata read) before this
  /// ever reaches native code — an out-of-range position throws
  /// [InvalidMediaException] in Dart rather than failing natively.
  final List<Duration> positions;

  final int maxWidth;
  final int maxHeight;
  final ImageFormat format;
  final int quality;

  @override
  String toString() =>
      'ThumbnailOptions(positions: $positions, maxWidth: $maxWidth, '
      'maxHeight: $maxHeight, format: $format, quality: $quality)';
}
