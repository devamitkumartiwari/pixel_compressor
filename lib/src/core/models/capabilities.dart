import '../../platform/messages.g.dart';
import '../../platform/wire_mapping.dart';
import '../enums/codec_support_status.dart';

/// A snapshot of which codecs this device can encode with, and the
/// largest resolution its hardware encoder supports.
class Capabilities {
  const Capabilities({
    required this.h264Encode,
    required this.hevcEncode,
    required this.aacEncode,
    required this.webpEncode,
    required this.heicEncode,
    this.maxHardwareWidth,
    this.maxHardwareHeight,
  });

  factory Capabilities.fromMessage(CapabilitiesReportMessage message) =>
      Capabilities(
        h264Encode: message.h264Encode.toDart(),
        hevcEncode: message.hevcEncode.toDart(),
        aacEncode: message.aacEncode.toDart(),
        webpEncode: message.webpEncode.toDart(),
        heicEncode: message.heicEncode.toDart(),
        maxHardwareWidth: message.maxHardwareWidth,
        maxHardwareHeight: message.maxHardwareHeight,
      );

  final CodecSupportStatus h264Encode;
  final CodecSupportStatus hevcEncode;
  final CodecSupportStatus aacEncode;
  final CodecSupportStatus webpEncode;
  final CodecSupportStatus heicEncode;

  final int? maxHardwareWidth;
  final int? maxHardwareHeight;

  bool get supportsHevc => hevcEncode == CodecSupportStatus.supported;
  bool get supportsWebp => webpEncode == CodecSupportStatus.supported;
  bool get supportsHeic => heicEncode == CodecSupportStatus.supported;

  @override
  String toString() =>
      'Capabilities(h264: $h264Encode, hevc: $hevcEncode, aac: $aacEncode, '
      'webp: $webpEncode, heic: $heicEncode, maxHw: ${maxHardwareWidth}x$maxHardwareHeight)';
}
