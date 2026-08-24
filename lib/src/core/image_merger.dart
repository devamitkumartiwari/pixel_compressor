import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'exceptions/pixel_compressor_exception.dart';
import 'merge_geometry.dart';
import 'models/media_source.dart';
import 'models/merge_options.dart';
import 'models/merge_result.dart';

/// Pure-Dart image merging (vertical/horizontal stitching) — reachable as
/// `PixelCompressor.merge`. Unlike every other concern on the facade, this
/// does no native platform-channel work: it's `dart:ui` `Canvas` drawing
/// entirely on the Dart side, and only ever produces PNG bytes (`dart:ui`
/// has no built-in JPEG/WebP/HEIC encoder). To get another format or hit
/// a target file size, pipe the PNG through `PixelCompressor.image.compress`:
///
/// ```dart
/// final merged = await PixelCompressor.merge.combine(sources);
/// final jpeg = await PixelCompressor.image.compress(
///   MediaSource.file(merged.outputFile),
///   options: const ImageCompressOptions(
///     format: ImageFormat.jpeg,
///     targetSizeBytes: 500 * 1024,
///   ),
/// );
/// ```
class ImageMerger {
  ImageMerger.internal();

  /// Decodes every source in [inputs], stitches them per [options], and
  /// writes the result to `options.outputPath` (or a temp file). Requires
  /// at least 2 sources.
  Future<MergeResult> combine(
    List<MediaSource> inputs, {
    MergeOptions options = const MergeOptions(),
  }) async {
    final stopwatch = Stopwatch()..start();

    if (inputs.length < 2) {
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'At least 2 images are required to merge (got ${inputs.length}).',
      );
    }

    final images = <ui.Image>[];
    try {
      for (final source in inputs) {
        images.add(await decode(source));
      }

      final sizes = images
          .map(
            (img) =>
                (width: img.width.toDouble(), height: img.height.toDouble()),
          )
          .toList();
      final canvasSize = computeMergeCanvasSize(
        sizes: sizes,
        direction: options.direction,
        spacing: options.spacing,
        scaleToFit: options.scaleToFit,
      );
      if (canvasSize.width <= 0 || canvasSize.height <= 0) {
        throw InvalidMediaException(
          nativeCode: 'invalid_media',
          nativeMessage:
              'Computed a zero-size merged canvas from the given sources.',
        );
      }
      final placements = computeMergePlacements(
        sizes: sizes,
        direction: options.direction,
        spacing: options.spacing,
        scaleToFit: options.scaleToFit,
        alignment: options.alignment,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      );
      if (options.background.a != 0) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
          ui.Paint()..color = options.background,
        );
      }
      for (var i = 0; i < images.length; i++) {
        final img = images[i];
        final p = placements[i];
        canvas.drawImageRect(
          img,
          ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          ui.Rect.fromLTWH(p.dx, p.dy, p.width, p.height),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
      }

      final picture = recorder.endRecording();
      final ui.Image rendered;
      try {
        rendered = await picture.toImage(
          canvasSize.width.round(),
          canvasSize.height.round(),
        );
      } finally {
        picture.dispose();
      }

      final Uint8List pngBytes;
      try {
        final byteData = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) {
          throw const EncodingException(
            nativeCode: 'encoding_error',
            nativeMessage: 'Failed to encode the merged canvas to PNG.',
          );
        }
        pngBytes = byteData.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }

      final outputPath = options.outputPath ?? _defaultOutputPath();
      await _writeOutput(outputPath, pngBytes);

      stopwatch.stop();
      return MergeResult(
        outputPath: outputPath,
        outputBytes: pngBytes,
        width: canvasSize.width.round(),
        height: canvasSize.height.round(),
        sourceCount: inputs.length,
        duration: stopwatch.elapsed,
      );
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }

  /// Decodes one source into a `dart:ui` [ui.Image] — the same decode
  /// path [combine] uses internally, exposed so a live `MergeView`
  /// preview shares identical [PixelCompressorException] handling with
  /// the headless path. The caller owns the returned image and must call
  /// `.dispose()` on it when done.
  Future<ui.Image> decode(MediaSource source) async {
    final Uint8List bytes;
    try {
      bytes = await File(source.resolvedPath).readAsBytes();
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13) {
        throw PermissionDeniedException(
          nativeCode: 'permission_denied',
          nativeMessage:
              'Permission denied reading "${source.resolvedPath}": '
              '${e.message}',
        );
      }
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage: 'Could not read "${source.resolvedPath}": ${e.message}',
      );
    }

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      throw DecodingException(
        nativeCode: 'decoding_error',
        nativeMessage: 'Could not decode image at "${source.resolvedPath}": $e',
      );
    }
  }

  String _defaultOutputPath() {
    final name =
        'pixel_compressor_merge_${DateTime.now().microsecondsSinceEpoch}.png';
    return '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
  }

  Future<void> _writeOutput(String path, Uint8List bytes) async {
    final file = File(path);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 28) {
        throw InsufficientStorageException(
          nativeCode: 'insufficient_storage',
          nativeMessage: 'Not enough free space to write "$path": ${e.message}',
        );
      }
      throw EncodingException(
        nativeCode: 'encoding_error',
        nativeMessage:
            'Could not write merged output to "$path": '
            '${e.message}',
      );
    }
  }
}
