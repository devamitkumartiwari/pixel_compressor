import 'dart:typed_data' as typed_data;

import 'package:cross_file/cross_file.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'compress_format.dart';
import 'resize.dart';
import 'validator.dart';

const _kUnsupportedHint =
    '\n\nCommon causes:\n'
    '  * Calling from a background Isolate - either move to the main '
    'isolate, or call BackgroundIsolateBinaryMessenger.ensureInitialized(...) '
    'inside the isolate before use.\n'
    '  * No implementation registered for the current platform (Windows is '
    'not supported; Linux is not supported).\n'
    '  * Release/minified web build where platform detection fails - try '
    'flutter build web --profile to confirm.';

abstract class PixelImageCompressPlatform() extends PlatformInterface {
  this : super(token: _token);

  static const _token = Object();

  static PixelImageCompressPlatform instance = UnsupportedPixelImageCompress();

  PixelImageFormatValidator get validator;

  Future<void> showNativeLog(bool value);

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
  });

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
  });

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
  });

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
  });

  void ignoreCheckSupportPlatform(bool bool);
}

class UnsupportedPixelImageCompress() extends PixelImageCompressPlatform {
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
  }) {
    throw UnimplementedError(
      'PixelImageCompressor.compressAsset is not available.'
      '$_kUnsupportedHint',
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
  }) {
    throw UnimplementedError(
      'PixelImageCompressor.compressFileToBytes is not available.'
      '$_kUnsupportedHint',
    );
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
  }) {
    throw UnimplementedError(
      'PixelImageCompressor.compressFileToFile is not available.'
      '$_kUnsupportedHint',
    );
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
  }) {
    throw UnimplementedError(
      'PixelImageCompressor.compressBytes is not available.'
      '$_kUnsupportedHint',
    );
  }

  @override
  Future<void> showNativeLog(bool value) {
    throw UnimplementedError(
      'PixelImageCompressor.nativeLogEnabled is not available.'
      '$_kUnsupportedHint',
    );
  }

  @override
  void ignoreCheckSupportPlatform(bool bool) {
    throw UnimplementedError(
      'PixelImageCompressor.ignoreCheckSupportPlatform is not available.'
      '$_kUnsupportedHint',
    );
  }

  @override
  PixelImageFormatValidator get validator => throw UnimplementedError(
    'PixelImageCompressor.validator is not available.'
    '$_kUnsupportedHint',
  );
}
