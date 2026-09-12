import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../core/enums/compression_stage.dart';
import '../core/enums/image_format.dart';
import '../core/exceptions/pixel_compressor_exception.dart';
import '../core/image_format_sniffer.dart';
import '../core/models/compression_result.dart';
import '../core/models/image_compress_options.dart';
import '../core/models/media_source.dart';
import '../core/models/progress_event.dart';
import '../core/target_size_loop.dart';
import 'image_compressor_backend.dart';
import 'progress_hub.dart';
import 'task_registry_dart.dart';

ImageCompressorBackend createImageCompressorBackend() =>
    _WebImageCompressorBackend();

String _mimeFor(ImageFormat format) => switch (format) {
  ImageFormat.jpeg => 'image/jpeg',
  ImageFormat.png => 'image/png',
  ImageFormat.webp => 'image/webp',
  ImageFormat.heic => 'image/heic',
};

String _extensionFor(ImageFormat format) => switch (format) {
  ImageFormat.jpeg => 'jpg',
  ImageFormat.png => 'png',
  ImageFormat.webp => 'webp',
  ImageFormat.heic => 'heic',
};

/// Web image compression: browser `<canvas>`/`OffscreenCanvas` only, no
/// external JS libraries. Only `MediaSource.bytes`/`.asset` are usable —
/// there's no real filesystem path in a browser. HEIC always throws
/// (no browser can encode it); WebP is attempted but the resulting blob's
/// MIME type is checked explicitly, since some browsers silently fall
/// back to PNG for an unsupported encode target rather than failing, and
/// this codebase never accepts a silent format substitution.
class _WebImageCompressorBackend implements ImageCompressorBackend {
  @override
  Future<CompressionResult> compress(
    String taskId,
    MediaSource input,
    ImageCompressOptions options,
  ) async {
    _report(taskId, CompressionStage.preparing, 0);

    if (input.filePath != null) {
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'On web, PixelCompressor.image.compress only supports '
            'MediaSource.bytes/.asset — a real filesystem path is not usable '
            'in a browser.',
        taskId: taskId,
      );
    }

    _report(taskId, CompressionStage.analyzing, 5);
    final sourceBytes = await input.readBytes();
    final format = options.format ?? sniffImageFormat(sourceBytes);
    if (format == ImageFormat.heic) {
      throw UnsupportedCodecException(
        nativeCode: 'unsupported_codec',
        nativeMessage: 'HEIC encode is not supported by any browser.',
        taskId: taskId,
      );
    }

    final rotationDegrees = options.rotationDegrees;
    if (rotationDegrees != 0 &&
        rotationDegrees != 90 &&
        rotationDegrees != 180 &&
        rotationDegrees != 270) {
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'rotationDegrees must be one of 0, 90, 180, 270, got $rotationDegrees',
        taskId: taskId,
      );
    }

    final token = TaskRegistryDart.instance.registerDart(taskId);
    try {
      token.throwIfCancelled(taskId);
      _report(taskId, CompressionStage.decoding, 10);
      final sourceBlob = web.Blob(
        [sourceBytes.toJS].toJS,
        web.BlobPropertyBag(type: _mimeFor(format)),
      );
      final bitmap = await web.window
          .createImageBitmap(
            sourceBlob,
            web.ImageBitmapOptions(
              imageOrientation: options.autoCorrectOrientation
                  ? 'from-image'
                  : 'none',
            ),
          )
          .toDart;

      try {
        token.throwIfCancelled(taskId);
        final mimeType = _mimeFor(format);
        final Uint8List encodedBytes;

        if (options.targetSizeBytes != null) {
          encodedBytes = await runTargetSizeLoop(
            targetSizeBytes: options.targetSizeBytes!,
            attempt: (quality, maxLongestEdge) {
              token.throwIfCancelled(taskId);
              return _renderAndEncode(
                bitmap: bitmap,
                rotationDegrees: rotationDegrees,
                maxWidth: maxLongestEdge ?? options.maxWidth,
                maxHeight: maxLongestEdge ?? options.maxHeight,
                mimeType: mimeType,
                format: format,
                quality: quality,
                taskId: taskId,
              );
            },
            onAttempt: (attemptNumber, maxAttempts, note) {
              final percent = 10 + (attemptNumber / maxAttempts) * 80;
              _report(taskId, CompressionStage.encoding, percent, note: note);
            },
          );
        } else {
          _report(taskId, CompressionStage.encoding, 50);
          final result = await _renderAndEncode(
            bitmap: bitmap,
            rotationDegrees: rotationDegrees,
            maxWidth: options.maxWidth,
            maxHeight: options.maxHeight,
            mimeType: mimeType,
            format: format,
            quality: options.quality.clamp(1, 100),
            taskId: taskId,
          );
          encodedBytes = result.bytes;
        }

        token.throwIfCancelled(taskId);
        _report(taskId, CompressionStage.finalizing, 95);
        final originalSizeBytes = sourceBytes.lengthInBytes;
        final outputSizeBytes = encodedBytes.lengthInBytes;
        final ratio = originalSizeBytes > 0
            ? outputSizeBytes / originalSizeBytes
            : 0.0;

        _report(taskId, CompressionStage.completed, 100);

        // No real filesystem exists on web — outputBytes is the primary
        // result channel; outputPath is a placeholder purely for
        // CompressionResult's API-shape compatibility.
        return CompressionResult(
          outputPath: 'web://pixel_compressor/$taskId.${_extensionFor(format)}',
          originalSizeBytes: originalSizeBytes,
          outputSizeBytes: outputSizeBytes,
          compressionRatio: ratio,
          duration: Duration.zero,
          codec: format.name,
          format: format.name,
          outputBytes: encodedBytes,
        );
      } finally {
        bitmap.close();
      }
    } finally {
      TaskRegistryDart.instance.unregister(taskId);
    }
  }

  Future<TargetSizeAttempt> _renderAndEncode({
    required web.ImageBitmap bitmap,
    required int rotationDegrees,
    required int? maxWidth,
    required int? maxHeight,
    required String mimeType,
    required ImageFormat format,
    required int quality,
    required String taskId,
  }) async {
    final naturalWidth = bitmap.width;
    final naturalHeight = bitmap.height;
    final isQuarterTurn = rotationDegrees == 90 || rotationDegrees == 270;
    final rotatedWidth = isQuarterTurn ? naturalHeight : naturalWidth;
    final rotatedHeight = isQuarterTurn ? naturalWidth : naturalHeight;

    final scale = _fitScale(rotatedWidth, rotatedHeight, maxWidth, maxHeight);
    final canvasWidth = max(1, (rotatedWidth * scale).round());
    final canvasHeight = max(1, (rotatedHeight * scale).round());

    final canvas = web.OffscreenCanvas(canvasWidth, canvasHeight);
    final ctx =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;

    final drawWidth = naturalWidth * scale;
    final drawHeight = naturalHeight * scale;
    ctx.save();
    ctx.translate(canvasWidth / 2, canvasHeight / 2);
    if (rotationDegrees != 0) {
      ctx.rotate(rotationDegrees * pi / 180);
    }
    ctx.drawImage(
      bitmap,
      -drawWidth / 2,
      -drawHeight / 2,
      drawWidth,
      drawHeight,
    );
    ctx.restore();

    final blob = await canvas
        .convertToBlob(
          web.ImageEncodeOptions(type: mimeType, quality: quality / 100),
        )
        .toDart;

    if (format == ImageFormat.webp && blob.type != 'image/webp') {
      throw UnsupportedCodecException(
        nativeCode: 'unsupported_codec',
        nativeMessage:
            'This browser does not support WebP encoding via canvas '
            '(got "${blob.type}" instead).',
        taskId: taskId,
      );
    }

    final buffer = await blob.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    return TargetSizeAttempt(
      bytes: bytes,
      longestEdge: max(canvasWidth, canvasHeight),
    );
  }

  double _fitScale(int width, int height, int? maxWidth, int? maxHeight) {
    if (maxWidth == null && maxHeight == null) return 1.0;
    final widthScale = maxWidth != null ? maxWidth / width : double.maxFinite;
    final heightScale = maxHeight != null
        ? maxHeight / height
        : double.maxFinite;
    return [widthScale, heightScale, 1.0].reduce(min);
  }

  void _report(
    String taskId,
    CompressionStage stage,
    num percent, {
    String? note,
  }) {
    ProgressHub.instance.emit(
      ProgressEvent(
        taskId: taskId,
        stage: stage,
        percent: percent.toDouble(),
        note: note,
      ),
    );
  }
}
