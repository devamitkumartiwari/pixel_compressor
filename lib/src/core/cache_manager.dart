import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';

/// Management of pixel_compressor's own output cache directory —
/// reachable as `PixelCompressor.cache`. Only applies to results written
/// without an explicit `outputPath`.
class CacheManager {
  CacheManager.internal();

  final CacheHostApi _api = CacheHostApi();

  /// Total bytes currently used by cached compression output.
  Future<int> size() => mapPlatformErrors(() => _api.getCacheSize());

  /// Deletes every cached output file.
  Future<void> clear() => mapPlatformErrors(() => _api.clearCache());
}
