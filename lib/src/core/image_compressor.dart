import 'dart:async';

import '../platform/image_backend.dart';
import '../platform/image_compressor_backend.dart';
import '../platform/progress_hub.dart';
import '../platform/task_id_generator.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'models/batch_item_result.dart';
import 'models/batch_result.dart';
import 'models/compression_result.dart';
import 'models/image_compress_options.dart';
import 'models/media_source.dart';
import 'models/progress_event.dart';
import 'source_deletion.dart';

/// Image compression — reachable as `PixelCompressor.image`.
class ImageCompressor {
  ImageCompressor.internal();

  final ImageCompressorBackend _backend = createImageCompressorBackend();

  /// Compresses a single image. Pass [onProgress] to observe stage/percent
  /// updates for this task while it runs.
  ///
  /// JPEG/PNG compression runs entirely in Dart; WebP/HEIC (and every
  /// format on native platforms other than web) run through the native
  /// engines. See `image_backend_io.dart`/`image_backend_web.dart`.
  Future<CompressionResult> compress(
    MediaSource input, {
    ImageCompressOptions options = const ImageCompressOptions(),
    void Function(ProgressEvent event)? onProgress,
  }) async {
    final taskId = generateTaskId('img');
    final subscription = onProgress == null
        ? null
        : ProgressHub.instance.stream
              .where((e) => e.taskId == taskId)
              .listen(onProgress);
    try {
      final result = await _backend.compress(taskId, input, options);
      if (options.deleteSourceOnSuccess) {
        await deleteSourceIfRequested(input, result.outputPath);
      }
      return result;
    } finally {
      await subscription?.cancel();
    }
  }

  /// Compresses [inputs] one at a time with the same [options], continuing
  /// past a per-item failure instead of aborting the whole batch. [onProgress]
  /// reports `(itemIndex, totalItems, event)` for whichever item is currently
  /// running.
  Future<BatchResult> compressBatch(
    List<MediaSource> inputs, {
    ImageCompressOptions options = const ImageCompressOptions(),
    void Function(int itemIndex, int totalItems, ProgressEvent event)?
    onProgress,
  }) async {
    final items = <BatchItemResult>[];
    for (var i = 0; i < inputs.length; i++) {
      final source = inputs[i];
      try {
        final result = await compress(
          source,
          options: options,
          onProgress: onProgress == null
              ? null
              : (event) => onProgress(i, inputs.length, event),
        );
        items.add(BatchItemResult.success(source: source, result: result));
      } on PixelCompressorException catch (error) {
        items.add(BatchItemResult.failure(source: source, error: error));
      }
    }
    return BatchResult(items: items);
  }
}
