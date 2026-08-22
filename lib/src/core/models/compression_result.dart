import 'dart:io';

import '../../platform/messages.g.dart';

/// The outcome of a successful image or video compression.
class CompressionResult {
  const CompressionResult({
    required this.outputPath,
    required this.originalSizeBytes,
    required this.outputSizeBytes,
    required this.compressionRatio,
    required this.duration,
    required this.codec,
    required this.format,
  });

  factory CompressionResult.fromMessage(CompressionResultMessage message) =>
      CompressionResult(
        outputPath: message.outputPath,
        originalSizeBytes: message.originalSizeBytes,
        outputSizeBytes: message.outputSizeBytes,
        compressionRatio: message.compressionRatio,
        duration: Duration(milliseconds: message.durationMs),
        codec: message.codec,
        format: message.format,
      );

  /// Where the compressed file was written.
  final String outputPath;

  final int originalSizeBytes;
  final int outputSizeBytes;

  /// `outputSizeBytes / originalSizeBytes` — smaller is better.
  final double compressionRatio;

  /// Wall-clock time the native side spent compressing.
  final Duration duration;

  /// The codec actually used (may differ from a requested `auto`/preset).
  final String codec;

  /// The output format/container actually used.
  final String format;

  File get outputFile => File(outputPath);

  int get savedBytes => originalSizeBytes - outputSizeBytes;

  /// How much smaller the output is than the original, as a 0-100 percent.
  double get savedPercent =>
      originalSizeBytes == 0 ? 0 : (savedBytes / originalSizeBytes) * 100;

  @override
  String toString() =>
      'CompressionResult(outputPath: $outputPath, '
      '$originalSizeBytes -> $outputSizeBytes bytes, '
      '${savedPercent.toStringAsFixed(1)}% saved, codec: $codec)';
}
