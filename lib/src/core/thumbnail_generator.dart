import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';
import '../platform/task_id_generator.dart';
import '../platform/wire_mapping.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'metadata_reader.dart';
import 'models/media_source.dart';
import 'models/thumbnail_options.dart';
import 'models/thumbnail_result.dart';

/// Video thumbnail generation — reachable as `PixelCompressor.thumbnails`.
class ThumbnailGenerator {
  ThumbnailGenerator.internal(this._metadata);

  final ThumbnailHostApi _api = ThumbnailHostApi();
  final MetadataReader _metadata;

  /// Captures a frame at each position in [ThumbnailOptions.positions].
  /// Positions are checked against the source's real duration first — an
  /// out-of-range position throws [InvalidMediaException] before any
  /// native work happens, rather than failing partway through native
  /// decoding.
  Future<List<ThumbnailResult>> generate(
    MediaSource input,
    ThumbnailOptions options,
  ) async {
    final info = await _metadata.read(input);
    final durationMs = info.duration?.inMilliseconds;
    if (durationMs != null) {
      for (final position in options.positions) {
        if (position.inMilliseconds < 0 ||
            position.inMilliseconds > durationMs) {
          throw InvalidMediaException(
            nativeCode: 'invalid_media',
            nativeMessage:
                'Thumbnail position $position is outside the source duration '
                '(${info.duration}).',
          );
        }
      }
    }

    final taskId = generateTaskId('thumb');
    final messages = await mapPlatformErrors(
      () => _api.generateThumbnails(
        ThumbnailRequest(
          taskId: taskId,
          sourcePath: input.resolvedPath,
          positionsMs: options.positions.map((d) => d.inMilliseconds).toList(),
          maxWidth: options.maxWidth,
          maxHeight: options.maxHeight,
          format: options.format.toWire(),
          quality: options.quality,
        ),
      ),
      taskId: taskId,
    );
    return messages.map(ThumbnailResult.fromMessage).toList();
  }
}
