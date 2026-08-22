/// Native image and video compression for Flutter — resizing, format
/// conversion, rotation and EXIF handling, target-size compression,
/// thumbnail generation, media metadata, batch processing with progress
/// and cancellation, capability detection, and cache management.
///
/// All processing happens on-device via platform codecs
/// (`MediaCodec`/`MediaMuxer` on Android, `AVFoundation`/`VideoToolbox`/
/// `ImageIO` on iOS/macOS) — nothing is ever uploaded anywhere.
///
/// Entry point is the [PixelCompressor] facade:
///
/// ```dart
/// final result = await PixelCompressor.image.compress(
///   MediaSource.file(file),
///   options: const ImageCompressOptions(quality: 80, maxWidth: 1920),
/// );
/// ```
library;

export 'src/core/cache_manager.dart';
export 'src/core/capability_checker.dart';
export 'src/core/enums/codec_support_status.dart';
export 'src/core/enums/compression_mode.dart';
export 'src/core/enums/compression_stage.dart';
export 'src/core/enums/exif_policy.dart';
export 'src/core/enums/image_format.dart';
export 'src/core/enums/media_type.dart';
export 'src/core/enums/quality_preset.dart';
export 'src/core/enums/task_outcome.dart';
export 'src/core/enums/video_codec.dart';
export 'src/core/exceptions/pixel_compressor_exception.dart';
export 'src/core/image_compressor.dart';
export 'src/core/metadata_reader.dart';
export 'src/core/models/batch_item_result.dart';
export 'src/core/models/batch_result.dart';
export 'src/core/models/capabilities.dart';
export 'src/core/models/compression_result.dart';
export 'src/core/models/image_compress_options.dart';
export 'src/core/models/media_info.dart';
export 'src/core/models/media_source.dart';
export 'src/core/models/progress_event.dart';
export 'src/core/models/thumbnail_options.dart';
export 'src/core/models/thumbnail_result.dart';
export 'src/core/models/video_compress_options.dart';
export 'src/core/task_manager.dart';
export 'src/core/thumbnail_generator.dart';
export 'src/core/video_compressor.dart';

import 'src/core/cache_manager.dart';
import 'src/core/capability_checker.dart';
import 'src/core/image_compressor.dart';
import 'src/core/metadata_reader.dart';
import 'src/core/models/progress_event.dart';
import 'src/core/task_manager.dart';
import 'src/core/thumbnail_generator.dart';
import 'src/core/video_compressor.dart';
import 'src/platform/progress_hub.dart';

/// Single entry point for every pixel_compressor feature, grouped by
/// concern:
///
/// * [image] / [video] — compress a file or a batch of files.
/// * [thumbnails] — capture frames from a video.
/// * [metadata] — read dimensions/duration/codec info without compressing.
/// * [capabilities] — check which codecs this device can encode with.
/// * [cache] — inspect/clear pixel_compressor's own output cache.
/// * [tasks] — cancel a running compression by its task id.
/// * [progressStream] — every task's progress, tagged by task id; prefer
///   the `onProgress` callback on `compress()` unless you need a single
///   stream across multiple concurrent tasks.
abstract final class PixelCompressor {
  static final ImageCompressor image = ImageCompressor.internal();
  static final VideoCompressor video = VideoCompressor.internal();
  static final MetadataReader metadata = MetadataReader.internal();
  static final ThumbnailGenerator thumbnails = ThumbnailGenerator.internal(
    metadata,
  );
  static final CapabilityChecker capabilities = CapabilityChecker.internal();
  static final CacheManager cache = CacheManager.internal();
  static final TaskManager tasks = TaskManager.internal();

  static Stream<ProgressEvent> get progressStream =>
      ProgressHub.instance.stream;
}
