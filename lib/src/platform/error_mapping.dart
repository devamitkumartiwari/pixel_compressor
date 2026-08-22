import 'package:flutter/services.dart';

import '../core/exceptions/pixel_compressor_exception.dart';

/// Runs [body] and converts any [PlatformException] thrown by the
/// generated Pigeon HostApi calls into the matching typed
/// [PixelCompressorException] subclass, keyed off the native `code`.
///
/// Every native HostApi implementation is expected to throw a
/// `FlutterError`/`PigeonError` whose `code` is one of the strings below —
/// this is the single place that mapping happens, so call sites never see
/// a raw `PlatformException`.
Future<T> mapPlatformErrors<T>(
  Future<T> Function() body, {
  String? taskId,
}) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    throw _mapCode(e.code, e.message, taskId);
  }
}

PixelCompressorException _mapCode(
  String code,
  String? message,
  String? taskId,
) {
  switch (code) {
    case 'unsupported_media':
      return UnsupportedMediaException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'unsupported_codec':
      return UnsupportedCodecException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'invalid_media':
      return InvalidMediaException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'permission_denied':
      return PermissionDeniedException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'cancelled':
      return CompressionCancelledException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'insufficient_storage':
      return InsufficientStorageException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'encoding_error':
      return EncodingException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'decoding_error':
      return DecodingException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'metadata_error':
      return MetadataException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'target_size_unachievable':
      return TargetSizeException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    case 'platform_not_supported':
      return PlatformNotSupportedException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
    default:
      return UnknownPixelCompressorException(
        nativeCode: code,
        nativeMessage: message,
        taskId: taskId,
      );
  }
}
