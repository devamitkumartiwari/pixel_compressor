package com.therivanta.pixelcompressor.errors

import com.therivanta.pixelcompressor.FlutterError
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CancellationException

/**
 * One factory per wire error code from `lib/src/platform/error_mapping.dart`.
 * Every error thrown from native code (whether directly by engine logic or
 * via [Throwable.toPixelCompressorError] as a safety net) must use one of
 * these exact `code` strings — Dart has no fallback for anything else other
 * than [UnknownPixelCompressorException], which we never want to hit
 * deliberately.
 */
object PixelCompressorErrors {
  fun unsupportedMedia(message: String, details: Any? = null) =
    FlutterError("unsupported_media", message, details)

  fun unsupportedCodec(message: String, details: Any? = null) =
    FlutterError("unsupported_codec", message, details)

  fun invalidMedia(message: String, details: Any? = null) =
    FlutterError("invalid_media", message, details)

  fun permissionDenied(message: String, details: Any? = null) =
    FlutterError("permission_denied", message, details)

  fun cancelled(message: String = "Task was cancelled", details: Any? = null) =
    FlutterError("cancelled", message, details)

  fun insufficientStorage(message: String, details: Any? = null) =
    FlutterError("insufficient_storage", message, details)

  fun encodingError(message: String, details: Any? = null) =
    FlutterError("encoding_error", message, details)

  fun decodingError(message: String, details: Any? = null) =
    FlutterError("decoding_error", message, details)

  fun metadataError(message: String, details: Any? = null) =
    FlutterError("metadata_error", message, details)

  fun targetSizeUnachievable(message: String, details: Any? = null) =
    FlutterError("target_size_unachievable", message, details)

  fun platformNotSupported(message: String, details: Any? = null) =
    FlutterError("platform_not_supported", message, details)
}

/**
 * Safety-net mapper for exceptions not already thrown as a typed
 * [FlutterError] by engine code — e.g. an unexpected [IOException] bubbling
 * out of a codec call. Never lets a raw/unknown code reach Dart.
 */
fun Throwable.toPixelCompressorError(): FlutterError {
  if (this is FlutterError) return this
  if (this is CancellationException) {
    return PixelCompressorErrors.cancelled(message ?: "Task was cancelled")
  }
  return when (this) {
    is FileNotFoundException ->
      PixelCompressorErrors.invalidMedia(message ?: "Source file not found", toString())
    is SecurityException ->
      PixelCompressorErrors.permissionDenied(message ?: "Permission denied", toString())
    is IOException ->
      PixelCompressorErrors.decodingError(message ?: "I/O error reading media", toString())
    else ->
      PixelCompressorErrors.encodingError(
        message ?: (javaClass.simpleName + ": unexpected native error"),
        toString(),
      )
  }
}
