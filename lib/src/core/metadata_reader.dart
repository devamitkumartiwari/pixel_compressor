import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';
import 'models/media_info.dart';
import 'models/media_source.dart';

/// Media metadata reads — reachable as `PixelCompressor.metadata`.
class MetadataReader {
  MetadataReader.internal();

  final MetadataHostApi _api = MetadataHostApi();

  /// Reads dimensions/duration/codec/EXIF info from [input] without
  /// compressing it.
  Future<MediaInfo> read(MediaSource input) async {
    final message = await mapPlatformErrors(
      () => _api.getMediaInfo(MediaInfoRequest(sourcePath: input.resolvedPath)),
    );
    return MediaInfo.fromMessage(message);
  }
}
