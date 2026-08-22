import '../exceptions/pixel_compressor_exception.dart';
import '../models/media_source.dart';
import 'compression_result.dart';

/// The outcome of one item inside a [PixelCompressor.image] or
/// [PixelCompressor.video] `compressBatch` call. Exactly one of [result] or
/// [error] is non-null — a batch keeps going after a per-item failure
/// rather than aborting the whole job.
class BatchItemResult {
  const BatchItemResult.success({
    required this.source,
    required CompressionResult this.result,
  }) : error = null;

  const BatchItemResult.failure({
    required this.source,
    required PixelCompressorException this.error,
  }) : result = null;

  final MediaSource source;
  final CompressionResult? result;
  final PixelCompressorException? error;

  bool get succeeded => result != null;

  @override
  String toString() => succeeded
      ? 'BatchItemResult.success(${source.resolvedPath} -> $result)'
      : 'BatchItemResult.failure(${source.resolvedPath}: $error)';
}
