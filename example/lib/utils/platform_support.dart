import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

/// What pixel_compressor supports on the platform the example runs on.
/// Controls that don't apply are shown disabled with a hint rather than
/// hidden, so the support matrix stays visible.
abstract final class PlatformSupport() {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// File-path APIs (`compressFileTo*`, batch, merge `outputPath`).
  static bool get files => !kIsWeb;

  /// `PixelVideoCompressor` (compression, thumbnails, media info).
  static bool get video => !kIsWeb;

  /// EXIF handling and rotation are native-only; the web canvas ignores them.
  static bool get exif => !kIsWeb;

  static String get name {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  /// Output formats this platform can encode.
  static bool supportsFormat(PixelImageFormat format) => switch (format) {
    .heic => !kIsWeb,
    .webp => !isMacOS,
    _ => true,
  };

  static String? formatHint(PixelImageFormat format) =>
      supportsFormat(format) ? null : 'Not on $name';
}
