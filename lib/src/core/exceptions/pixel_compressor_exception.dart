/// Base type for every exception this package throws.
///
/// Native error codes and messages always flow through as [nativeCode] and
/// [nativeMessage] — this package never collapses a real native failure
/// into a generic "compression failed".
sealed class PixelCompressorException implements Exception {
  const PixelCompressorException({
    required this.nativeCode,
    this.nativeMessage,
    this.taskId,
  });

  /// The stable error code reported by the native side (e.g.
  /// `encoding_error`).
  final String nativeCode;

  /// The native error message, if one was provided.
  final String? nativeMessage;

  /// The task this error belongs to, if the failing call was tied to one.
  final String? taskId;

  @override
  String toString() =>
      '$runtimeType($nativeCode${nativeMessage != null ? ': $nativeMessage' : ''})';
}

/// The input file is not an image or video format this package can read.
final class UnsupportedMediaException extends PixelCompressorException {
  const UnsupportedMediaException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The requested codec (e.g. HEVC, WebP encode) isn't available on this
/// device or platform.
final class UnsupportedCodecException extends PixelCompressorException {
  const UnsupportedCodecException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The source file couldn't be parsed as valid media, or a request
/// parameter is out of range for the given source (e.g. a thumbnail
/// position past the end of a video).
final class InvalidMediaException extends PixelCompressorException {
  const InvalidMediaException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The source path couldn't be opened due to a permissions error.
final class PermissionDeniedException extends PixelCompressorException {
  const PermissionDeniedException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The task was cancelled before it completed.
final class CompressionCancelledException extends PixelCompressorException {
  const CompressionCancelledException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// There wasn't enough free disk space to write the output file.
final class InsufficientStorageException extends PixelCompressorException {
  const InsufficientStorageException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The native encoder failed, or produced an empty/missing output file.
final class EncodingException extends PixelCompressorException {
  const EncodingException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The native decoder failed to read the source media.
final class DecodingException extends PixelCompressorException {
  const DecodingException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// Reading or writing media metadata (EXIF, container info) failed.
final class MetadataException extends PixelCompressorException {
  const MetadataException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// A `targetSizeBytes` request could not be satisfied even after every
/// fallback (resolution stepping, bitrate clamping) was exhausted.
final class TargetSizeException extends PixelCompressorException {
  const TargetSizeException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// The requested operation isn't supported on the current platform (e.g.
/// video compression on Web).
final class PlatformNotSupportedException extends PixelCompressorException {
  const PlatformNotSupportedException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}

/// An error was reported with a code this package doesn't recognize —
/// should not normally happen, but kept as a safety net instead of
/// crashing the mapping layer on an unexpected code.
final class UnknownPixelCompressorException extends PixelCompressorException {
  const UnknownPixelCompressorException({
    required super.nativeCode,
    super.nativeMessage,
    super.taskId,
  });
}
