import '../core/models/compression_result.dart';
import '../core/models/image_compress_options.dart';
import '../core/models/media_source.dart';

/// The pluggable implementation behind [ImageCompressor.compress] —
/// swapped between an io backend (native WebP/HEIC + Dart JPEG/PNG) and a
/// web backend (Dart-only, canvas-based) via a conditional import, so the
/// public `ImageCompressor` API stays identical across platforms.
abstract class ImageCompressorBackend {
  Future<CompressionResult> compress(
    String taskId,
    MediaSource input,
    ImageCompressOptions options,
  );
}
