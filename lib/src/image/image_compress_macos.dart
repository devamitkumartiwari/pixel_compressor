// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

import 'compress_format.dart';
import 'resize.dart';
import 'errors.dart';
import 'image_compress_platform.dart';
import 'validator.dart';

class PixelImageCompressMacos() extends PixelImageCompressPlatform {
  static const _channel = MethodChannel('pixel_compressor/image');

  /// For flutter plugin registration.
  static void registerWith() {
    PixelImageCompressPlatform.instance = PixelImageCompressMacos();
  }

  Future<void> checkSupport(PixelImageFormat format) async {
    if (!(await validator.checkSupportPlatform(format))) {
      throw PixelCompressError(
        '${format.name} output is not available on macOS (no encoder).',
        code: 'unsupported_format',
      );
    }
  }

  /// See `PixelImageCompressMobile._invoke` for rationale — native
  /// `FlutterError` results become [PixelCompressError] on the Dart side.
  Future<T?> _invoke<T>(String method, [dynamic args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PixelCompressError(e.message ?? e.code, code: e.code);
    }
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
    await checkSupport(format);

    final dstPath = await _invoke<String>('compressAndGetFile', {
      'path': path,
      'targetPath': targetPath,
      'minWidth': minWidth,
      'minHeight': minHeight,
      'inSampleSize': inSampleSize,
      'quality': quality,
      'rotate': rotate,
      'autoCorrectionAngle': autoCorrectionAngle,
      'format': format.index,
      'keepExif': keepExif,
      ..._resizeWireMap(maxWidth, maxHeight, exactSize),
      'numberOfRetries': numberOfRetries,
    });

    if (dstPath == null) {
      throw PixelCompressError('Compress returned no file', code: 'unknown');
    }

    return XFile(dstPath);
  }

  @override
  Future<Uint8List> compressAsset(
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
    await checkSupport(format);

    final data = await rootBundle.load(assetName);
    final bytes = data.buffer.asUint8List();

    return compressBytes(
      bytes,
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

  @override
  Future<Uint8List> compressFileToBytes(
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
    await checkSupport(format);

    final result = await _invoke<Uint8List>('compressWithFile', {
      'path': path,
      'minWidth': minWidth,
      'minHeight': minHeight,
      'inSampleSize': inSampleSize,
      'quality': quality,
      'rotate': rotate,
      'autoCorrectionAngle': autoCorrectionAngle,
      'format': format.index,
      'keepExif': keepExif,
      ..._resizeWireMap(maxWidth, maxHeight, exactSize),
      'numberOfRetries': numberOfRetries,
    });

    if (result == null) {
      throw PixelCompressError('Compress returned no data', code: 'unknown');
    }

    return result;
  }

  @override
  Future<Uint8List> compressBytes(
    Uint8List image, {
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
    await checkSupport(format);

    final result = await _invoke<Uint8List>('compressWithList', {
      'list': image,
      'minWidth': minWidth,
      'minHeight': minHeight,
      'inSampleSize': inSampleSize,
      'quality': quality,
      'rotate': rotate,
      'autoCorrectionAngle': autoCorrectionAngle,
      'format': format.index,
      'keepExif': keepExif,
      ..._resizeWireMap(maxWidth, maxHeight, exactSize),
    });

    if (result == null) {
      throw PixelCompressError('Compress failed');
    }

    return result;
  }

  @override
  Future<void> showNativeLog(bool value) async {
    await _channel.invokeMethod('showLog', value);
  }

  @override
  PixelImageFormatValidator get validator => _validator;
  final PixelImageFormatValidator _validator = PixelImageFormatValidatorMacos(
    _channel,
  );

  @override
  void ignoreCheckSupportPlatform(bool value) {
    _validator.ignoreCheckSupportPlatform = value;
  }
}

class PixelImageFormatValidatorMacos(super.channel)
    extends PixelImageFormatValidator {
  @override
  Future<bool> checkSupportPlatform(PixelImageFormat format) async {
    if (ignoreCheckSupportPlatform) {
      return true;
    }

    if (format == .webp) {
      return false;
    }

    return true;
  }
}

Map<String, int> _resizeWireMap(
  int? maxWidth,
  int? maxHeight,
  PixelExactSize? exactSize,
) {
  final args = resizeWireArgs(
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    exactSize: exactSize,
  );
  return {
    'maxWidth': args[0],
    'maxHeight': args[1],
    'exactWidth': args[2],
    'exactHeight': args[3],
    'fit': args[4],
    'padColor': args[5],
  };
}
