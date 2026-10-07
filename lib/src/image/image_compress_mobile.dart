import 'dart:async';
import 'dart:io';
import 'dart:typed_data' as typed_data;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

import 'compress_format.dart';
import 'resize.dart';
import 'errors.dart';
import 'image_compress_platform.dart';
import 'validator.dart';

/// Image Compress plugin.
///
/// Method in the static class will help you to compress images,
/// most methods will return [Uint8List].
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
class PixelImageCompressMobile() extends PixelImageCompressPlatform {
  static const _channel = MethodChannel('pixel_compressor/image');

  @override
  PixelImageFormatValidator get validator => _validator;
  final PixelImageFormatValidator _validator = PixelImageFormatValidator(
    _channel,
  );

  /// For flutter plugin registration.
  static void registerWith() {
    PixelImageCompressPlatform.instance = PixelImageCompressMobile();
  }

  /// Wrap [MethodChannel.invokeMethod] so native `result.error(...)` /
  /// `replyError(...)` calls surface as [PixelCompressError] on the Dart side
  /// instead of leaking as [PlatformException] or (worse) a silent null
  /// return type-cast failure. The native code carries a stable failure
  /// code (see [PixelCompressError.code]) and a human message.
  Future<T?> _invoke<T>(String method, [dynamic args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PixelCompressError(e.message ?? e.code, code: e.code);
    }
  }

  @override
  Future<typed_data.Uint8List> compressAsset(
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
    await _validator.checkSupportPlatform(format);
    final img = AssetImage(assetName);
    const config = ImageConfiguration();
    final AssetBundleImageKey key = await img.obtainKey(config);
    final ByteData data = await key.bundle.load(key.name);
    final uint8List = data.buffer.asUint8List();
    if (uint8List.isEmpty) {
      throw PixelCompressError('Asset $assetName is empty.', code: 'io_failed');
    }
    return compressBytes(
      uint8List,
      minHeight: minHeight,
      minWidth: minWidth,
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

  @override
  Future<typed_data.Uint8List> compressFileToBytes(
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
    if (numberOfRetries <= 0) {
      throw PixelCompressError("numberOfRetries can't be null or less than 0");
    }
    if (!File(path).existsSync()) {
      throw PixelCompressError('Image file does not exist in $path.');
    }
    await _validator.checkSupportPlatform(format);
    final result = await _invoke<typed_data.Uint8List>('compressWithFile', [
      path,
      minWidth,
      minHeight,
      quality,
      rotate,
      autoCorrectionAngle,
      _convertTypeToInt(format),
      keepExif,
      inSampleSize,
      numberOfRetries,
      ...resizeWireArgs(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        exactSize: exactSize,
      ),
    ]);
    if (result == null) {
      throw PixelCompressError('Compress returned no data', code: 'unknown');
    }
    return result;
  }

  @override
  Future<typed_data.Uint8List> compressBytes(
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
    if (image.isEmpty) {
      throw PixelCompressError('The image is empty.');
    }
    await _validator.checkSupportPlatform(format);
    final result = await _invoke<typed_data.Uint8List>('compressWithList', [
      image,
      minWidth,
      minHeight,
      quality,
      rotate,
      autoCorrectionAngle,
      _convertTypeToInt(format),
      keepExif,
      inSampleSize,
      ...resizeWireArgs(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        exactSize: exactSize,
      ),
    ]);
    // Native failures now surface via `_invoke` as `PixelCompressError`, so a null
    // result here means the native side responded with `success(null)` — which
    // shouldn't happen after Step 1. Guard defensively to avoid a TypeError.
    if (result == null) {
      throw PixelCompressError('Compress returned no data', code: 'unknown');
    }
    return result;
  }

  @override
  Future<void> showNativeLog(bool value) async {
    await _channel.invokeMethod('showLog', value);
  }

  @override
  Future<XFile> compressFileToFile(
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
    if (numberOfRetries <= 0) {
      throw PixelCompressError("numberOfRetries can't be null or less than 0");
    }
    if (!File(path).existsSync()) {
      throw PixelCompressError('Image file does not exist in $path.');
    }
    if (path == targetPath) {
      throw PixelCompressError(
        'Target path and source path cannot be the same.',
      );
    }
    _validator.checkFileNameAndFormat(targetPath, format);
    await _validator.checkSupportPlatform(format);
    final String? result = await _invoke<String>('compressWithFileAndGetFile', [
      path,
      minWidth,
      minHeight,
      quality,
      targetPath,
      rotate,
      autoCorrectionAngle,
      _convertTypeToInt(format),
      keepExif,
      inSampleSize,
      numberOfRetries,
      ...resizeWireArgs(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        exactSize: exactSize,
      ),
    ]);
    if (result == null) {
      throw PixelCompressError('Compress returned no file', code: 'unknown');
    }
    return XFile(result);
  }

  @override
  void ignoreCheckSupportPlatform(bool value) {
    _validator.ignoreCheckSupportPlatform = value;
  }
}

int _convertTypeToInt(PixelImageFormat format) => format.index;
