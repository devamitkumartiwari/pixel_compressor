import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'models/capabilities.dart';

/// Device codec capability detection — reachable as
/// `PixelCompressor.capabilities`.
class CapabilityChecker {
  CapabilityChecker.internal();

  final CapabilityHostApi _api = CapabilityHostApi();

  /// Reports which codecs this device can encode with, and the largest
  /// resolution its hardware encoder supports. Cheap to call, but not
  /// free — cache the result for the app session rather than calling this
  /// before every compression.
  ///
  /// Throws [PlatformNotSupportedException] on web — there's no native
  /// channel registered there to answer this.
  Future<Capabilities> check() async {
    if (kIsWeb) {
      throw const PlatformNotSupportedException(
        nativeCode: 'platform_not_supported',
        nativeMessage: 'PixelCompressor.capabilities is not supported on web.',
      );
    }
    final message = await mapPlatformErrors(() => _api.capabilities());
    return Capabilities.fromMessage(message);
  }
}
