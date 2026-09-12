import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/error_mapping.dart';
import '../platform/materialized_source.dart';
import '../platform/messages.g.dart';
import '../platform/task_id_generator.dart';
import '../platform/task_registry_dart.dart';
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
    if (kIsWeb) {
      throw const PlatformNotSupportedException(
        nativeCode: 'platform_not_supported',
        nativeMessage: 'PixelCompressor.thumbnails is not supported on web.',
      );
    }

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
    TaskRegistryDart.instance.registerNative(taskId);
    final materialized = await MaterializedSource.resolve(
      input,
      taskId: taskId,
      defaultExtensionHint: 'mp4',
    );
    try {
      final messages = await mapPlatformErrors(
        () => _api.generateThumbnails(
          ThumbnailRequest(
            taskId: taskId,
            sourcePath: materialized.path,
            positionsMs: options.positions
                .map((d) => d.inMilliseconds)
                .toList(),
            maxWidth: options.maxWidth,
            maxHeight: options.maxHeight,
            format: options.format.toWire(),
            quality: options.quality,
          ),
        ),
        taskId: taskId,
      );
      return messages.map(ThumbnailResult.fromMessage).toList();
    } finally {
      await materialized.cleanup();
      TaskRegistryDart.instance.unregister(taskId);
    }
  }
}
