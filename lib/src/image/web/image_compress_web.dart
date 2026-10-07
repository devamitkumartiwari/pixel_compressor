import 'dart:async';
import 'dart:typed_data' as typed_data;

import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

import '../compress_format.dart';
import '../resize.dart';
import '../image_compress_platform.dart';
import '../validator.dart';
import 'log.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'compressor.dart';

class PixelImageCompressWeb() extends PixelImageCompressPlatform {
  static void registerWith(Registrar registrar) {
    PixelImageCompressPlatform.instance = PixelImageCompressWeb();
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
    throw UnimplementedError('The method not support web');
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
    final asset = await rootBundle.load(assetName);
    final buffer = asset.buffer.asUint8List();
    return resizeWithList(
      buffer: buffer,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      format: format,
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
  }) {
    throw UnimplementedError('The method not support web');
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
    return resizeWithList(
      buffer: image,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      format: format,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      exactSize: exactSize,
    );
  }

  @override
  void ignoreCheckSupportPlatform(bool bool) {}

  @override
  Future<void> showNativeLog(bool value) async {
    showLog = value;
  }

  @override
  PixelImageFormatValidator get validator => _PixelImageFormatValidatorWeb();
}

class _PixelImageFormatValidatorWeb() extends PixelImageFormatValidator {
  this : super(const MethodChannel('pixel_compressor/image'));

  @override
  void checkFileNameAndFormat(String name, PixelImageFormat format) {}
  @override
  Future<bool> checkSupportPlatform(PixelImageFormat format) async {
    return true;
  }
}
