import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/cache_manager.dart';
import '../core/enums/image_format.dart';
import '../core/exceptions/pixel_compressor_exception.dart';
import '../core/image_engine_dart.dart';
import '../core/image_format_sniffer.dart';
import '../core/models/compression_result.dart';
import '../core/models/image_compress_options.dart';
import '../core/models/media_source.dart';
import 'error_mapping.dart';
import 'image_compressor_backend.dart';
import 'materialized_source.dart';
import 'messages.g.dart';
import 'task_registry_dart.dart';
import 'wire_mapping.dart';

ImageCompressorBackend createImageCompressorBackend() =>
    _IoImageCompressorBackend();

String _extensionFor(ImageFormat format) => switch (format) {
  ImageFormat.jpeg => 'jpg',
  ImageFormat.png => 'png',
  ImageFormat.webp => 'webp',
  ImageFormat.heic => 'heic',
};

class _IoImageCompressorBackend implements ImageCompressorBackend {
  final ImageHostApi _imageApi = ImageHostApi();
  final CacheManager _cacheManager = CacheManager.internal();
  final ImageEngineDart _dartEngine = const ImageEngineDart();

  @override
  Future<CompressionResult> compress(
    String taskId,
    MediaSource input,
    ImageCompressOptions options,
  ) async {
    final effectiveFormat = await _resolveEffectiveFormat(
      input,
      options.format,
    );

    final CompressionResult result;
    if (effectiveFormat == ImageFormat.jpeg ||
        effectiveFormat == ImageFormat.png) {
      result = await _compressWithDartEngine(
        taskId,
        input,
        options,
        effectiveFormat,
      );
    } else {
      result = await _compressWithNativeEngine(taskId, input, options);
    }
    return result;
  }

  Future<ImageFormat> _resolveEffectiveFormat(
    MediaSource input,
    ImageFormat? requested,
  ) async {
    if (requested != null) return requested;
    final bytes = await _peekBytes(input);
    return sniffImageFormat(bytes);
  }

  /// Reads enough of [input] to sniff its format, without materializing a
  /// temp file for a bytes/asset source that might end up routed to the
  /// (still file-based) native WebP/HEIC engine.
  Future<Uint8List> _peekBytes(MediaSource input) async {
    try {
      return await input.readBytes();
    } on FileSystemException catch (e) {
      throw _mapReadError(e);
    }
  }

  Future<CompressionResult> _compressWithDartEngine(
    String taskId,
    MediaSource input,
    ImageCompressOptions options,
    ImageFormat format,
  ) async {
    final token = TaskRegistryDart.instance.registerDart(taskId);
    try {
      final Uint8List sourceBytes;
      try {
        sourceBytes = await input.readBytes();
      } on FileSystemException catch (e) {
        throw _mapReadError(e);
      }

      final outputPath =
          options.outputPath ??
          await _cacheManager.resolveOutputPath(
            CacheKind.images,
            _extensionFor(format),
          );

      var result = await _dartEngine.compress(
        taskId: taskId,
        sourceBytes: sourceBytes,
        format: format,
        options: options,
        outputPath: outputPath,
        cancellationToken: token,
      );
      if (options.returnBytes) {
        result = result.withOutputBytes(
          await File(result.outputPath).readAsBytes(),
        );
      }
      return result;
    } finally {
      TaskRegistryDart.instance.unregister(taskId);
    }
  }

  Future<CompressionResult> _compressWithNativeEngine(
    String taskId,
    MediaSource input,
    ImageCompressOptions options,
  ) async {
    TaskRegistryDart.instance.registerNative(taskId);
    final materialized = await MaterializedSource.resolve(
      input,
      taskId: taskId,
      defaultExtensionHint: 'jpg',
    );
    try {
      final message = await mapPlatformErrors(
        () => _imageApi.compressImage(
          ImageCompressRequest(
            taskId: taskId,
            sourcePath: materialized.path,
            outputPath: options.outputPath,
            format: options.format?.toWire(),
            quality: options.quality,
            maxWidth: options.maxWidth,
            maxHeight: options.maxHeight,
            rotationDegrees: options.rotationDegrees,
            exifPolicy: options.exifPolicy.toWire(),
            targetSizeBytes: options.targetSizeBytes,
            autoCorrectOrientation: options.autoCorrectOrientation,
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
      return result;
    } finally {
      await materialized.cleanup();
      TaskRegistryDart.instance.unregister(taskId);
    }
  }

  PixelCompressorException _mapReadError(FileSystemException e) {
    if (e.osError?.errorCode == 13) {
      return PermissionDeniedException(
        nativeCode: 'permission_denied',
        nativeMessage: 'Permission denied reading source: ${e.message}',
      );
    }
    return InvalidMediaException(
      nativeCode: 'invalid_media',
      nativeMessage: 'Could not read source: ${e.message}',
    );
  }
}
