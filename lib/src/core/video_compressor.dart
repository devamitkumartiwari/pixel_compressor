import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/error_mapping.dart';
import '../platform/materialized_source.dart';
import '../platform/messages.g.dart';
import '../platform/progress_hub.dart';
import '../platform/task_id_generator.dart';
import '../platform/task_registry_dart.dart';
import '../platform/wire_mapping.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'models/batch_item_result.dart';
import 'models/batch_result.dart';
import 'models/compression_result.dart';
import 'models/media_source.dart';
import 'models/progress_event.dart';
import 'models/video_compress_options.dart';
import 'source_deletion.dart';

/// Video compression — reachable as `PixelCompressor.video`.
class VideoCompressor {
  VideoCompressor.internal();

  final VideoHostApi _api = VideoHostApi();

  /// Compresses a single video. Pass [onProgress] to observe stage/percent
  /// updates for this task while it runs (video compression is typically
  /// long-running, so this is the primary way to drive a progress bar).
  Future<CompressionResult> compress(
    MediaSource input, {
    VideoCompressOptions options = const VideoCompressOptions(),
    void Function(ProgressEvent event)? onProgress,
  }) async {
    if (kIsWeb) {
      throw const PlatformNotSupportedException(
        nativeCode: 'platform_not_supported',
        nativeMessage: 'PixelCompressor.video is not supported on web.',
      );
    }

    final trimStart = options.trimStart;
    final trimEnd = options.trimEnd;
    if (trimStart != null && trimEnd != null && trimEnd <= trimStart) {
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'trimEnd ($trimEnd) must be after trimStart ($trimStart)',
      );
    }

    final taskId = generateTaskId('vid');
    final subscription = onProgress == null
        ? null
        : ProgressHub.instance.stream
              .where((e) => e.taskId == taskId)
              .listen(onProgress);
    TaskRegistryDart.instance.registerNative(taskId);
    final materialized = await MaterializedSource.resolve(
      input,
      taskId: taskId,
      defaultExtensionHint: 'mp4',
    );
    try {
      final message = await mapPlatformErrors(
        () => _api.compressVideo(
          VideoCompressRequest(
            taskId: taskId,
            sourcePath: materialized.path,
            outputPath: options.outputPath,
            preset: options.preset?.toWire(),
            codec: options.codec?.toWire(),
            maxWidth: options.maxWidth,
            maxHeight: options.maxHeight,
            fps: options.fps,
            bitrateBps: options.bitrateBps,
            audioEnabled: options.audioEnabled,
            audioBitrateBps: options.audioBitrateBps,
            trimStartMs: options.trimStart?.inMilliseconds,
            trimEndMs: options.trimEnd?.inMilliseconds,
            rotationDegrees: options.rotationDegrees,
            targetSizeBytes: options.targetSizeBytes,
            mode: options.mode.toWire(),
          ),
        ),
        taskId: taskId,
      );
      var result = CompressionResult.fromMessage(message);
      if (options.returnBytes) {
        result = result.withOutputBytes(
          await File(result.outputPath).readAsBytes(),
        );
      }
      if (options.deleteSourceOnSuccess) {
        await deleteSourceIfRequested(input, result.outputPath);
      }
      return result;
    } finally {
      await subscription?.cancel();
      await materialized.cleanup();
      TaskRegistryDart.instance.unregister(taskId);
    }
  }

  /// Compresses [inputs] one at a time with the same [options], continuing
  /// past a per-item failure instead of aborting the whole batch.
  Future<BatchResult> compressBatch(
    List<MediaSource> inputs, {
    VideoCompressOptions options = const VideoCompressOptions(),
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
