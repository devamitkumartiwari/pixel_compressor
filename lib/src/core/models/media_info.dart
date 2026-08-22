import '../../platform/messages.g.dart';
import '../../platform/wire_mapping.dart';
import '../enums/media_type.dart';

/// Metadata read from a source file without compressing it — dimensions,
/// duration, codecs, EXIF presence, etc.
class MediaInfo {
  const MediaInfo({
    required this.mediaType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.format,
    this.exifPresent,
    this.orientation,
    this.duration,
    this.fps,
    this.bitrateBps,
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.hasAudio,
  });

  factory MediaInfo.fromMessage(MediaInfoMessage message) => MediaInfo(
    mediaType: message.mediaType.toDart(),
    sizeBytes: message.sizeBytes,
    width: message.width,
    height: message.height,
    format: message.format,
    exifPresent: message.exifPresent,
    orientation: message.orientation,
    duration: message.durationMs == null
        ? null
        : Duration(milliseconds: message.durationMs!),
    fps: message.fps,
    bitrateBps: message.bitrateBps,
    videoCodec: message.videoCodec,
    audioCodec: message.audioCodec,
    container: message.container,
    hasAudio: message.hasAudio,
  );

  final MediaType mediaType;
  final int sizeBytes;

  final int? width;
  final int? height;

  /// The source's format/container, e.g. `jpeg`, `mp4`.
  final String? format;

  /// Images only — whether EXIF data is present.
  final bool? exifPresent;

  /// Images only — EXIF orientation tag value, if present.
  final int? orientation;

  /// Video only.
  final Duration? duration;
  final double? fps;
  final int? bitrateBps;
  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final bool? hasAudio;

  @override
  String toString() =>
      'MediaInfo(mediaType: $mediaType, ${width ?? '?'}x${height ?? '?'}, '
      'sizeBytes: $sizeBytes, format: $format, duration: $duration)';
}
