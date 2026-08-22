/// Explicit two-way conversion between the public Dart enums and the
/// Pigeon-generated wire enums. Kept isolated here so the public enums in
/// `core/enums/` stay free of any platform-channel concern.
library;

import '../core/enums/codec_support_status.dart';
import '../core/enums/compression_mode.dart';
import '../core/enums/compression_stage.dart';
import '../core/enums/exif_policy.dart';
import '../core/enums/image_format.dart';
import '../core/enums/media_type.dart';
import '../core/enums/quality_preset.dart';
import '../core/enums/task_outcome.dart';
import '../core/enums/video_codec.dart';
import 'messages.g.dart';

extension ImageFormatWireX on ImageFormat {
  ImageFormatWire toWire() => switch (this) {
    ImageFormat.jpeg => ImageFormatWire.jpeg,
    ImageFormat.png => ImageFormatWire.png,
    ImageFormat.webp => ImageFormatWire.webp,
    ImageFormat.heic => ImageFormatWire.heic,
  };
}

extension ImageFormatWireDecodeX on ImageFormatWire {
  ImageFormat toDart() => switch (this) {
    ImageFormatWire.jpeg => ImageFormat.jpeg,
    ImageFormatWire.png => ImageFormat.png,
    ImageFormatWire.webp => ImageFormat.webp,
    ImageFormatWire.heic => ImageFormat.heic,
  };
}

extension ExifPolicyWireX on ExifPolicy {
  ExifPolicyWire toWire() => switch (this) {
    ExifPolicy.keep => ExifPolicyWire.keep,
    ExifPolicy.strip => ExifPolicyWire.strip,
  };
}

extension QualityPresetWireX on QualityPreset {
  QualityPresetWire toWire() => switch (this) {
    QualityPreset.veryLow => QualityPresetWire.veryLow,
    QualityPreset.low => QualityPresetWire.low,
    QualityPreset.medium => QualityPresetWire.medium,
    QualityPreset.high => QualityPresetWire.high,
    QualityPreset.veryHigh => QualityPresetWire.veryHigh,
    QualityPreset.custom => QualityPresetWire.custom,
  };
}

extension VideoCodecWireX on VideoCodec {
  VideoCodecWire toWire() => switch (this) {
    VideoCodec.h264 => VideoCodecWire.h264,
    VideoCodec.hevc => VideoCodecWire.hevc,
    VideoCodec.auto => VideoCodecWire.auto,
  };
}

extension CompressionModeWireX on CompressionMode {
  CompressionModeWire toWire() => switch (this) {
    CompressionMode.manual => CompressionModeWire.manual,
    CompressionMode.smart => CompressionModeWire.smart,
  };
}

extension MediaTypeWireDecodeX on MediaTypeWire {
  MediaType toDart() => switch (this) {
    MediaTypeWire.image => MediaType.image,
    MediaTypeWire.video => MediaType.video,
    MediaTypeWire.unknown => MediaType.unknown,
  };
}

extension CodecSupportStatusWireDecodeX on CodecSupportStatusWire {
  CodecSupportStatus toDart() => switch (this) {
    CodecSupportStatusWire.supported => CodecSupportStatus.supported,
    CodecSupportStatusWire.unsupported => CodecSupportStatus.unsupported,
    CodecSupportStatusWire.unknown => CodecSupportStatus.unknown,
  };
}

extension CompressionStageWireDecodeX on CompressionStageWire {
  CompressionStage toDart() => switch (this) {
    CompressionStageWire.preparing => CompressionStage.preparing,
    CompressionStageWire.analyzing => CompressionStage.analyzing,
    CompressionStageWire.decoding => CompressionStage.decoding,
    CompressionStageWire.encoding => CompressionStage.encoding,
    CompressionStageWire.muxing => CompressionStage.muxing,
    CompressionStageWire.finalizing => CompressionStage.finalizing,
    CompressionStageWire.completed => CompressionStage.completed,
    CompressionStageWire.failed => CompressionStage.failed,
    CompressionStageWire.cancelled => CompressionStage.cancelled,
  };
}

extension TaskOutcomeWireDecodeX on TaskOutcomeWire {
  TaskOutcome toDart() => switch (this) {
    TaskOutcomeWire.completed => TaskOutcome.completed,
    TaskOutcomeWire.failed => TaskOutcome.failed,
    TaskOutcomeWire.cancelled => TaskOutcome.cancelled,
  };
}
