// Copyright 2026 Amit Kumar Tiwari
// Licensed under the Apache License, Version 2.0.
//
// Single source of truth for pixel_compressor's platform channel schema.
// Run `dart run pigeon --input pigeons/messages.dart` to regenerate:
//   - lib/src/platform/messages.g.dart
//   - android/src/main/kotlin/com/therivanta/pixelcompressor/Messages.g.kt
//   - ios/pixel_compressor/Sources/pixel_compressor/Messages.g.swift
// (macOS shares the iOS Swift sources by direct file copy — this repo is a
// single, non-federated plugin, so macos/ keeps its own Messages.g.swift
// copy in sync rather than depending on a separate Apple package.)

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/therivanta/pixelcompressor/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.therivanta.pixelcompressor'),
    swiftOut: 'ios/pixel_compressor/Sources/pixel_compressor/Messages.g.swift',
    dartOptions: DartOptions(),
  ),
)
// ---------------------------------------------------------------------------
// Wire enums
// ---------------------------------------------------------------------------
enum ImageFormatWire { jpeg, png, webp, heic }

enum ExifPolicyWire { keep, strip }

enum QualityPresetWire { veryLow, low, medium, high, veryHigh, custom }

enum VideoCodecWire { h264, hevc, auto }

enum CompressionModeWire { manual, smart }

enum MediaTypeWire { image, video, unknown }

enum CodecSupportStatusWire { supported, unsupported, unknown }

enum CompressionStageWire {
  preparing,
  analyzing,
  decoding,
  encoding,
  muxing,
  finalizing,
  completed,
  failed,
  cancelled,
}

enum TaskOutcomeWire { completed, failed, cancelled }

// ---------------------------------------------------------------------------
// Wire data classes
// ---------------------------------------------------------------------------

class ImageCompressRequest {
  ImageCompressRequest({
    required this.taskId,
    required this.sourcePath,
    required this.quality,
    required this.rotationDegrees,
    required this.exifPolicy,
    required this.autoCorrectOrientation,
    this.outputPath,
    this.format,
    this.maxWidth,
    this.maxHeight,
    this.targetSizeBytes,
  });

  final String taskId;
  final String sourcePath;
  final String? outputPath;
  final ImageFormatWire? format;
  final int quality;
  final int? maxWidth;
  final int? maxHeight;
  final int rotationDegrees;
  final ExifPolicyWire exifPolicy;
  final int? targetSizeBytes;

  /// Only consulted by the WebP/HEIC native engines — JPEG/PNG compression
  /// runs entirely in Dart and applies this itself before ever reaching a
  /// platform channel.
  final bool autoCorrectOrientation;
}

class VideoCompressRequest {
  VideoCompressRequest({
    required this.taskId,
    required this.sourcePath,
    required this.audioEnabled,
    required this.rotationDegrees,
    required this.mode,
    this.outputPath,
    this.preset,
    this.codec,
    this.maxWidth,
    this.maxHeight,
    this.fps,
    this.bitrateBps,
    this.audioBitrateBps,
    this.trimStartMs,
    this.trimEndMs,
    this.targetSizeBytes,
  });

  final String taskId;
  final String sourcePath;
  final String? outputPath;
  final QualityPresetWire? preset;
  final VideoCodecWire? codec;
  final int? maxWidth;
  final int? maxHeight;
  final int? fps;
  final int? bitrateBps;
  final bool audioEnabled;
  final int? audioBitrateBps;
  final int? trimStartMs;
  final int? trimEndMs;
  final int rotationDegrees;
  final int? targetSizeBytes;
  final CompressionModeWire mode;
}

class ThumbnailRequest {
  ThumbnailRequest({
    required this.taskId,
    required this.sourcePath,
    required this.positionsMs,
    required this.maxWidth,
    required this.maxHeight,
    required this.format,
    required this.quality,
  });

  final String taskId;
  final String sourcePath;

  /// Validated Dart-side (against the source's real duration, from a
  /// [MediaInfoRequest] pre-check) before this ever reaches native code —
  /// out-of-range positions throw `InvalidMediaException` in Dart rather
  /// than being handled by native bounds-checking.
  final List<int> positionsMs;
  final int maxWidth;
  final int maxHeight;
  final ImageFormatWire format;
  final int quality;
}

class MediaInfoRequest {
  MediaInfoRequest({required this.sourcePath});

  final String sourcePath;
}

class CompressionResultMessage {
  CompressionResultMessage({
    required this.outputPath,
    required this.originalSizeBytes,
    required this.outputSizeBytes,
    required this.compressionRatio,
    required this.durationMs,
    required this.codec,
    required this.format,
  });

  final String outputPath;
  final int originalSizeBytes;
  final int outputSizeBytes;
  final double compressionRatio;
  final int durationMs;
  final String codec;
  final String format;
}

class ThumbnailResultMessage {
  ThumbnailResultMessage({
    required this.outputPath,
    required this.positionMs,
    required this.width,
    required this.height,
  });

  final String outputPath;
  final int positionMs;
  final int width;
  final int height;
}

class MediaInfoMessage {
  MediaInfoMessage({
    required this.mediaType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.format,
    this.exifPresent,
    this.orientation,
    this.durationMs,
    this.fps,
    this.bitrateBps,
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.hasAudio,
  });

  final MediaTypeWire mediaType;
  final int? width;
  final int? height;
  final String? format;
  final int sizeBytes;
  final bool? exifPresent;
  final int? orientation;
  final int? durationMs;
  final double? fps;
  final int? bitrateBps;
  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final bool? hasAudio;
}

class CapabilitiesReportMessage {
  CapabilitiesReportMessage({
    required this.h264Encode,
    required this.hevcEncode,
    required this.aacEncode,
    required this.webpEncode,
    required this.heicEncode,
    this.maxHardwareWidth,
    this.maxHardwareHeight,
  });

  final CodecSupportStatusWire h264Encode;
  final CodecSupportStatusWire hevcEncode;
  final CodecSupportStatusWire aacEncode;
  final CodecSupportStatusWire webpEncode;
  final CodecSupportStatusWire heicEncode;
  final int? maxHardwareWidth;
  final int? maxHardwareHeight;
}

class ProgressEventMessage {
  ProgressEventMessage({
    required this.taskId,
    required this.stage,
    required this.percent,
    this.currentItemIndex,
    this.totalItems,
    this.note,
  });

  final String taskId;
  final CompressionStageWire stage;
  final double percent;
  final int? currentItemIndex;
  final int? totalItems;
  final String? note;
}

class TaskTerminalMessage {
  TaskTerminalMessage({
    required this.taskId,
    required this.outcome,
    this.result,
    this.errorCode,
    this.errorMessage,
  });

  final String taskId;
  final TaskOutcomeWire outcome;
  final CompressionResultMessage? result;
  final String? errorCode;
  final String? errorMessage;
}

// ---------------------------------------------------------------------------
// HostApis (Dart -> native, request/response, async)
// ---------------------------------------------------------------------------

@HostApi()
abstract class ImageHostApi {
  @async
  CompressionResultMessage compressImage(ImageCompressRequest request);
}

@HostApi()
abstract class VideoHostApi {
  @async
  CompressionResultMessage compressVideo(VideoCompressRequest request);
}

@HostApi()
abstract class ThumbnailHostApi {
  @async
  List<ThumbnailResultMessage> generateThumbnails(ThumbnailRequest request);
}

@HostApi()
abstract class MetadataHostApi {
  @async
  MediaInfoMessage getMediaInfo(MediaInfoRequest request);
}

@HostApi()
abstract class CapabilityHostApi {
  @async
  CapabilitiesReportMessage capabilities();
}

@HostApi()
abstract class TaskHostApi {
  @async
  bool cancel(String taskId);

  @async
  void cancelAll();

  @async
  List<String> activeTaskIds();
}

// ---------------------------------------------------------------------------
// FlutterApi (native -> Dart, progress streaming)
//
// One shared callback API, every call tagged with taskId, fanned out
// Dart-side into a broadcast Stream<ProgressEvent> filtered per task.
// Chosen over EventChannel: no per-stream channel lifecycle management is
// needed for arbitrary concurrent batch items, and it keeps full Pigeon
// type safety end to end.
// ---------------------------------------------------------------------------

@FlutterApi()
abstract class PixelCompressorProgressCallbackApi {
  void onProgress(ProgressEventMessage event);

  void onTaskTerminal(TaskTerminalMessage message);
}
