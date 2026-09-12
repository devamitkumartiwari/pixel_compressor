import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// No-op web plugin registration. `pixel_compressor` has no platform
/// channel on web at all — `PixelCompressor.image.compress` is intercepted
/// entirely in Dart (see `image_backend_web.dart`) before any channel call
/// would happen, and every other facade member throws
/// `PlatformNotSupportedException` on web. This class exists only so
/// Flutter's own tooling (`flutter doctor`, pub.dev's platform-support
/// detection) correctly reports this plugin as web-supported.
class PixelCompressorWebPlugin {
  static void registerWith(Registrar registrar) {}
}
