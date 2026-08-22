import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';
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
  Future<Capabilities> check() async {
    final message = await mapPlatformErrors(() => _api.capabilities());
    return Capabilities.fromMessage(message);
  }
}
