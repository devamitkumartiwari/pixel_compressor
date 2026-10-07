/// Image and video compression for Flutter.
///
/// * [PixelImageCompressor]: JPEG / PNG / WebP / HEIC compression, resize,
///   rotation and EXIF handling.
/// * [PixelVideoCompressor]: video compression, thumbnails and media info
///   (Media3 Transformer on Android,
///   AVFoundation on iOS/macOS).
///
/// ```dart
/// final bytes = await PixelImageCompressor.compressFileToBytes(
///   file.path,
///   minWidth: 1920,
///   minHeight: 1080,
///   quality: 80,
/// );
///
/// final info = await PixelVideoCompressor.compressVideoFile(
///   video.path,
///   quality: PixelVideoQuality.MediumQuality,
/// );
/// ```
library;

export 'package:cross_file/cross_file.dart' show XFile;

export 'src/image/compress_format.dart';
export 'src/image/errors.dart';
export 'src/image/image_info.dart';
export 'src/image/image_compress_platform.dart';
export 'src/image/pixel_image_compressor.dart';
export 'src/image/resize.dart' show PixelExactSize, PixelImageFit;
export 'src/image/validator.dart';
export 'src/merge/image_merger.dart' show PixelImageMerger;
export 'src/merge/merge_options.dart';
export 'src/merge/merge_view.dart';
export 'src/video/media_data.dart';
export 'src/video/media_info.dart';
export 'src/video/pixel_video_compressor.dart';
export 'src/video/subscription.dart';
export 'src/video/video_quality.dart';
