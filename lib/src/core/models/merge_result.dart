import 'dart:io';
import 'dart:typed_data';

/// The outcome of a successful [PixelCompressor.merge] call.
class MergeResult {
  const MergeResult({
    required this.outputPath,
    required this.outputBytes,
    required this.width,
    required this.height,
    required this.sourceCount,
    required this.duration,
  });

  /// Where the merged PNG was written — see `MergeOptions.outputPath`.
  final String outputPath;

  /// The encoded PNG bytes — so callers that only need bytes (e.g. to
  /// pipe straight into `PixelCompressor.image.compress`) don't have to
  /// re-read [outputFile].
  final Uint8List outputBytes;

  /// Pixel dimensions of the merged canvas.
  final int width;
  final int height;

  /// How many sources were merged to produce this result.
  final int sourceCount;

  /// Wall-clock time spent decoding + drawing + encoding.
  final Duration duration;

  File get outputFile => File(outputPath);

  int get outputSizeBytes => outputBytes.length;

  @override
  String toString() =>
      'MergeResult(outputPath: $outputPath, ${width}x$height, '
      'sourceCount: $sourceCount, outputSizeBytes: $outputSizeBytes, '
      'duration: $duration)';
}
