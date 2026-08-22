import Foundation

/// Factory functions for every wire error `code` the Dart side understands
/// (see `lib/src/platform/error_mapping.dart`), plus a safety-net mapper
/// for unexpected Swift errors bubbling up from engine code. Never throw a
/// raw `PigeonError` with an ad-hoc code from engine code — always go
/// through one of these so the exact set of 11 codes stays authoritative.
enum PixelCompressorError {
  static func unsupportedMedia(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "unsupported_media", message: message, details: details)
  }

  static func unsupportedCodec(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "unsupported_codec", message: message, details: details)
  }

  static func invalidMedia(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "invalid_media", message: message, details: details)
  }

  static func permissionDenied(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "permission_denied", message: message, details: details)
  }

  static func cancelled(_ message: String = "Task was cancelled", details: Sendable? = nil)
    -> PigeonError
  {
    PigeonError(code: "cancelled", message: message, details: details)
  }

  static func insufficientStorage(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "insufficient_storage", message: message, details: details)
  }

  static func encodingError(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "encoding_error", message: message, details: details)
  }

  static func decodingError(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "decoding_error", message: message, details: details)
  }

  static func metadataError(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "metadata_error", message: message, details: details)
  }

  static func targetSizeUnachievable(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "target_size_unachievable", message: message, details: details)
  }

  static func platformNotSupported(_ message: String, details: Sendable? = nil) -> PigeonError {
    PigeonError(code: "platform_not_supported", message: message, details: details)
  }

  /// Safety-net mapper for any `Error` bubbling out of engine code that
  /// isn't already a `PigeonError` — converts it into an `encoding_error`
  /// (the closest generic bucket) rather than letting an unrecognized code
  /// reach Dart, where it would fall through to `UnknownPixelCompressorException`.
  static func map(_ error: Error) -> PigeonError {
    if let pigeonError = error as? PigeonError {
      return pigeonError
    }
    let nsError = error as NSError
    return encodingError("\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)")
  }
}
