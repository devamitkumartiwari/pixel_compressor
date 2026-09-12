import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/error_mapping.dart';
import '../platform/file_prefix_reader.dart';
import '../platform/materialized_source.dart';
import '../platform/messages.g.dart';
import '../platform/task_id_generator.dart';
import '../platform/task_registry_dart.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'image_metadata_reader_dart.dart';
import 'models/media_info.dart';
import 'models/media_source.dart';

/// Media metadata reads — reachable as `PixelCompressor.metadata`.
class MetadataReader {
  MetadataReader.internal();

  final MetadataHostApi _api = MetadataHostApi();

  /// Reads dimensions/duration/codec/EXIF info from [input] without
  /// compressing it.
  ///
  /// JPEG/PNG sources are read directly from their header bytes in pure
  /// Dart (see `image_metadata_reader_dart.dart`) — no native call, no
  /// temp-file materialization. Anything else (WebP, HEIC, video, or a
  /// source the Dart reader doesn't confidently recognize) falls back to
  /// the native `MetadataHostApi` unchanged.
  Future<MediaInfo> read(MediaSource input) async {
    if (kIsWeb) {
      throw const PlatformNotSupportedException(
        nativeCode: 'platform_not_supported',
        nativeMessage: 'PixelCompressor.metadata is not supported on web.',
      );
    }

    final prefix = await readSourcePrefix(input);
    final dartResult = tryReadImageMetadataDart(
      prefix.bytes,
      sizeBytes: prefix.totalSizeBytes,
    );
    if (dartResult != null) return dartResult;

    final taskId = generateTaskId('meta');
    TaskRegistryDart.instance.registerNative(taskId);
    final materialized = await MaterializedSource.resolve(
      input,
      taskId: taskId,
    );
    try {
      final message = await mapPlatformErrors(
        () =>
            _api.getMediaInfo(MediaInfoRequest(sourcePath: materialized.path)),
      );
      return MediaInfo.fromMessage(message);
    } finally {
      await materialized.cleanup();
      TaskRegistryDart.instance.unregister(taskId);
    }
  }
}
