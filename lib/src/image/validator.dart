import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'compress_format.dart';
import 'errors.dart';

class PixelImageFormatValidator(this.channel) {
  final MethodChannel channel;

  bool ignoreCheckExtName = false;
  bool ignoreCheckSupportPlatform = false;

  void checkFileNameAndFormat(String name, PixelImageFormat format) {
    if (ignoreCheckExtName) {
      return;
    }
    final lower = name.toLowerCase();
    late final Iterable<String> allowedExts;
    late final String formatLabel;
    if (format == .jpeg) {
      allowedExts = const ['.jpg', '.jpeg'];
      formatLabel = 'jpeg';
    } else if (format == .png) {
      allowedExts = const ['.png'];
      formatLabel = 'png';
    } else if (format == .heic) {
      allowedExts = const ['.heic'];
      formatLabel = 'heic';
    } else if (format == .webp) {
      allowedExts = const ['.webp'];
      formatLabel = 'webp';
    } else {
      return;
    }
    final ok = allowedExts.any(lower.endsWith);
    if (!ok) {
      final expected = allowedExts.join(' or ');
      final msg =
          'PixelImageFormat.$formatLabel requires the target file name to end '
          'with $expected. Got: "$name". '
          'If you deliberately want to bypass this check (for example the '
          'target extension does not match the encoded format), set '
          'PixelImageCompressor.validator.ignoreCheckExtName = true.';
      assert(false, msg);
      throw ArgumentError.value(name, 'name', msg);
    }
  }

  /// Whether this platform can encode [format].
  ///
  /// Throws a [PixelCompressError] with code `unsupported_format` when it
  /// can't. HEIC on Android can still fail later with the same code if the
  /// device has no hardware HEIF encoder.
  Future<bool> checkSupportPlatform(PixelImageFormat format) async {
    if (ignoreCheckSupportPlatform) {
      return true;
    }
    final supported = switch (format) {
      .jpeg || .png => true,
      // The package's minimums (iOS 16, Android API 28) already cover HEIC
      // and WebP on both platforms.
      .heic || .webp => _isAndroid || _isIOS,
    };
    if (!supported) {
      throw PixelCompressError(
        '${format.name} output is only available on Android and iOS.',
        code: 'unsupported_format',
      );
    }
    return true;
  }

  // Not `dart:io` Platform, so the package stays WASM-compatible. On the web
  // defaultTargetPlatform is the browser's OS, hence the kIsWeb guard.
  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == .iOS;
  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == .android;
}
