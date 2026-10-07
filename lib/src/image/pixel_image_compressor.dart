import 'dart:async';
import 'dart:typed_data' as typed_data;

import 'package:cross_file/cross_file.dart';

import 'compress_format.dart';
import 'errors.dart';
import 'image_compress_platform.dart';
import 'image_info.dart';
import 'resize.dart';
import 'validator.dart';

/// Image Compress plugin.
///
/// Method in the static class will help you to compress images,
/// most methods will return [typed_data.Uint8List].
///
/// You can use `Image.memory` to display image:
/// ```dart
/// Uint8List uint8List;
/// ImageProvider provider = MemoryImage(uint8List);
/// ```
///
/// or
///
/// ```dart
/// Uint8List uint8List;
/// Image.memory(uint8List)
/// ```
///
/// The returned image will retain the proportion of the original image.
/// Compress image will remove its EXIF info. and the result is in jpeg format.
/// Rotation is also supported.
class PixelImageCompressor._() {
  static PixelImageCompressPlatform get _platform => .instance;

  static PixelImageFormatValidator get validator => _platform.validator;

  static set nativeLogEnabled(bool value) {
    _platform.showNativeLog(value);
  }

  /// Compress image from [typed_data.Uint8List] to [typed_data.Uint8List].
  static Future<typed_data.Uint8List> compressBytes(
    typed_data.Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
  }) async {
    return _platform.compressBytes(
      image,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      rotate: rotate,
      inSampleSize: inSampleSize,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
    );
  }

  /// Compress file of [path] to [typed_data.Uint8List].
  static Future<typed_data.Uint8List> compressFileToBytes(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
    int numberOfRetries = 5,
  }) async {
    return _platform.compressFileToBytes(
      path,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      rotate: rotate,
      inSampleSize: inSampleSize,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
      numberOfRetries: numberOfRetries,
    );
  }

  /// From [path] to [targetPath]
  static Future<XFile> compressFileToFile(
    String path,
    String targetPath, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
    int numberOfRetries = 5,
  }) async {
    // Guard against source and target resolving to the same file. The native
    // Android/iOS handlers open the target for writing (truncating it) before
    // they read the source, so a same-path call would silently corrupt the
    // source before compression could read it.
    final normalizedSource = Uri.file(path).normalizePath().toFilePath();
    final normalizedTarget = Uri.file(targetPath).normalizePath().toFilePath();
    if (normalizedSource == normalizedTarget) {
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'compressFileToFile source and targetPath resolve to the same file '
            '($normalizedSource). Use compressFileToBytes to get bytes only, '
            'or pass a different targetPath.',
      );
    }
    return _platform.compressFileToFile(
      path,
      targetPath,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      rotate: rotate,
      inSampleSize: inSampleSize,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
      numberOfRetries: numberOfRetries,
    );
  }

  /// From asset [assetName] to [typed_data.Uint8List]
  static Future<typed_data.Uint8List> compressAsset(
    String assetName, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
  }) async {
    return _platform.compressAsset(
      assetName,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      rotate: rotate,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
    );
  }

  /// [compressFileToBytes] plus the output's size and format.
  static Future<PixelImageResult> compressFileWithInfo(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
    int numberOfRetries = 5,
  }) async {
    final bytes = await compressFileToBytes(
      path,
      minWidth: minWidth,
      minHeight: minHeight,
      inSampleSize: inSampleSize,
      quality: quality,
      rotate: rotate,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
      numberOfRetries: numberOfRetries,
    );
    return PixelImageResult(bytes, _infoOf(bytes));
  }

  /// [compressBytes] plus the output's size and format.
  static Future<PixelImageResult> compressBytesWithInfo(
    typed_data.Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
  }) async {
    final bytes = await compressBytes(
      image,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      rotate: rotate,
      inSampleSize: inSampleSize,
      autoCorrectionAngle: autoCorrectionAngle,
      format: format,
      keepExif: keepExif,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
    );
    return PixelImageResult(bytes, _infoOf(bytes));
  }

  /// Compresses [paths] with up to [concurrency] files in flight.
  ///
  /// Results come back in input order. A failing file doesn't stop the
  /// batch: its [PixelBatchItem.error] is set instead. [onProgress] is called
  /// after each file with (done, total).
  static Future<List<PixelBatchItem>> compressFilesToBytes(
    List<String> paths, {
    int concurrency = 2,
    void Function(int done, int total)? onProgress,
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    PixelImageFormat format = .jpeg,
    bool keepExif = false,
    int? maxWidth,
    int? maxHeight,
    PixelExactSize? exactSize,
    int numberOfRetries = 5,
  }) async {
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
    }
    final results = List<PixelBatchItem?>.filled(paths.length, null);
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (next < paths.length) {
        final index = next++;
        final path = paths[index];
        try {
          final result = await compressFileWithInfo(
            path,
            minWidth: minWidth,
            minHeight: minHeight,
            inSampleSize: inSampleSize,
            quality: quality,
            rotate: rotate,
            autoCorrectionAngle: autoCorrectionAngle,
            format: format,
            keepExif: keepExif,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            exactSize: exactSize,
            numberOfRetries: numberOfRetries,
          );
          results[index] = PixelBatchItem._(
            path,
            result.bytes,
            result.info,
            null,
          );
        } on PixelCompressError catch (e) {
          results[index] = PixelBatchItem._(path, null, null, e);
        } catch (e) {
          results[index] = PixelBatchItem._(
            path,
            null,
            null,
            PixelCompressError(e.toString(), code: 'unknown'),
          );
        }
        done++;
        onProgress?.call(done, paths.length);
      }
    }

    final workers = concurrency < paths.length ? concurrency : paths.length;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return List.unmodifiable(results.cast<PixelBatchItem>());
  }

  static PixelImageInfo _infoOf(typed_data.Uint8List bytes) {
    final info = PixelImageInfo.fromBytes(bytes);
    if (info == null) {
      throw PixelCompressError(
        'Could not read the output image header',
        code: 'unknown',
      );
    }
    return info;
  }

  static void ignoreCheckSupportPlatform(bool value) {
    _platform.ignoreCheckSupportPlatform(value);
  }
}

/// One file's outcome in [PixelImageCompressor.compressFilesToBytes].
class const PixelBatchItem._(this.path, this.bytes, this.info, this.error) {
  final String path;

  /// Compressed bytes, or null when [error] is set.
  final typed_data.Uint8List? bytes;

  /// Output size and format, or null when [error] is set.
  final PixelImageInfo? info;

  final PixelCompressError? error;

  bool get isSuccess => error == null;
}
