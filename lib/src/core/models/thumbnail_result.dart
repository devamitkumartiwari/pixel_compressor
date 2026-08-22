import 'dart:io';

import '../../platform/messages.g.dart';

/// One generated thumbnail frame.
class ThumbnailResult {
  const ThumbnailResult({
    required this.outputPath,
    required this.position,
    required this.width,
    required this.height,
  });

  factory ThumbnailResult.fromMessage(ThumbnailResultMessage message) =>
      ThumbnailResult(
        outputPath: message.outputPath,
        position: Duration(milliseconds: message.positionMs),
        width: message.width,
        height: message.height,
      );

  final String outputPath;

  /// Where in the source video this frame was captured.
  final Duration position;

  final int width;
  final int height;

  File get outputFile => File(outputPath);

  @override
  String toString() =>
      'ThumbnailResult(outputPath: $outputPath, position: $position, ${width}x$height)';
}
