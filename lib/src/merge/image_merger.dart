import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../image/compress_format.dart';
import '../image/errors.dart';
import '../image/image_info.dart';
import '../image/pixel_image_compressor.dart';
import 'merge_geometry.dart';
import 'merge_io.dart' if (dart.library.js_interop) 'merge_io_web.dart';
import 'merge_options.dart';

/// Combines several images into one, entirely on the Dart side (works on
/// every platform including the web).
///
/// Built to not fail on large inputs: sizes are read from the image headers,
/// the canvas is clamped to the output limits first, and every image is then
/// decoded directly at the size it's drawn at.
abstract final class PixelImageMerger() {
  /// Merges [sources] (at least 2) according to [options].
  ///
  /// Throws [PixelCompressError] with code `invalid_input` (fewer than 2
  /// sources, empty source), `io_failed` (unreadable file/asset, or the
  /// output couldn't be written), `decode_failed` (a source isn't a
  /// decodable image; the message names its index), `unsupported_format`
  /// or `encode_failed`.
  static Future<PixelMergeResult> merge(
    List<PixelMergeSource> sources, {
    PixelMergeOptions options = const PixelMergeOptions(),
  }) async {
    final stopwatch = Stopwatch()..start();
    final image = await renderMerge(sources, options);
    final width = image.width;
    final height = image.height;
    final Uint8List bytes;
    try {
      bytes = await _encode(image, options);
    } finally {
      image.dispose();
    }

    final path = options.outputPath;
    if (path != null) {
      try {
        await writeMergeFile(path, bytes);
      } on UnsupportedError catch (e) {
        throw PixelCompressError('${e.message}', code: 'invalid_input');
      } catch (e) {
        throw PixelCompressError(
          'Could not write "$path": $e',
          code: 'io_failed',
        );
      }
    }

    return PixelMergeResult(
      bytes: bytes,
      width: width,
      height: height,
      format: options.format,
      path: path,
      sourceCount: sources.length,
      elapsed: stopwatch.elapsed,
    );
  }
}

/// Renders [sources] into one `ui.Image` (caller disposes). Shared by
/// [PixelImageMerger.merge] and `PixelMergeView`, so preview and export
/// always match. Not exported.
Future<ui.Image> renderMerge(
  List<PixelMergeSource> sources,
  PixelMergeOptions options,
) async {
  if (sources.length < 2) {
    throw PixelCompressError(
      'At least 2 images are required to merge (got ${sources.length}).',
      code: 'invalid_input',
    );
  }

  final encoded = <Uint8List>[];
  for (var i = 0; i < sources.length; i++) {
    encoded.add(await _load(sources[i], i));
  }
  final sizes = <MergeImageSize>[];
  for (var i = 0; i < encoded.length; i++) {
    sizes.add(await _measure(encoded[i], i));
  }

  final layout = computeMergeLayout(sizes: sizes, options: options);
  final width = layout.width.round().clamp(1, kMergeMaxSide);
  final height = layout.height.round().clamp(1, kMergeMaxSide);

  final images = <ui.Image>[];
  ui.Picture? picture;
  try {
    for (var i = 0; i < encoded.length; i++) {
      final p = layout.placements[i];
      images.add(
        await _decodeAt(
          encoded[i],
          i,
          p.width.round().clamp(1, kMergeMaxSide),
          p.height.round().clamp(1, kMergeMaxSide),
        ),
      );
    }

    final recorder = ui.PictureRecorder();
    final bounds = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final canvas = ui.Canvas(recorder, bounds);
    // JPEG and HEIC have no alpha: transparency would come out black.
    final opaque = options.format == .jpeg || options.format == .heic;
    var background = options.background;
    if (opaque && background.a < 1) {
      background = background.a == 0
          ? const ui.Color(0xFFFFFFFF)
          : background.withValues(alpha: 1);
    }
    if (background.a > 0) {
      canvas.drawRect(bounds, ui.Paint()..color = background);
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    // Corner radius and padding are in pre-clamp pixels, like spacing.
    final radius = options.cornerRadius * layout.scale;
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      final p = layout.placements[i];
      final dst = ui.Rect.fromLTWH(p.dx, p.dy, p.width, p.height);
      if (radius > 0) {
        canvas.save();
        canvas.clipRRect(
          ui.RRect.fromRectAndRadius(dst, ui.Radius.circular(radius)),
        );
      }
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        paint,
      );
      if (radius > 0) canvas.restore();
    }
    picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } catch (e) {
      throw PixelCompressError(
        'Could not render the ${width}x$height merged image: $e',
        code: 'encode_failed',
      );
    }
  } finally {
    picture?.dispose();
    for (final image in images) {
      image.dispose();
    }
  }
}

Future<Uint8List> _load(PixelMergeSource source, int index) async {
  final Uint8List bytes;
  try {
    bytes = switch (source) {
      PixelMergeBytesSource(:final bytes) => bytes,
      PixelMergeFileSource(:final path) => await readMergeFile(path),
      PixelMergeAssetSource(:final name) => (await rootBundle.load(
        name,
      )).buffer.asUint8List(),
    };
  } on UnsupportedError catch (e) {
    throw PixelCompressError(
      'Source $index ($source): ${e.message}',
      code: 'invalid_input',
    );
  } catch (e) {
    throw PixelCompressError(
      'Source $index ($source) could not be read: $e',
      code: 'io_failed',
    );
  }
  if (bytes.isEmpty) {
    throw PixelCompressError(
      'Source $index ($source) is empty.',
      code: 'invalid_input',
    );
  }
  return bytes;
}

/// Displayed size from the header; falls back to the engine's descriptor
/// for formats the header parser doesn't know.
Future<MergeImageSize> _measure(Uint8List bytes, int index) async {
  final info = PixelImageInfo.fromBytes(bytes);
  if (info != null && info.width > 0 && info.height > 0) {
    return (width: info.width.toDouble(), height: info.height.toDouble());
  }
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (
      width: descriptor.width.toDouble(),
      height: descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    if (size.width > 0 && size.height > 0) return size;
  } catch (_) {
    // Reported below.
  }
  throw PixelCompressError(
    'Source $index is not a decodable image.',
    code: 'decode_failed',
  );
}

/// Decodes straight to the drawn size, so memory stays bounded by the
/// output. If the engine can't decode the format (e.g. HEIC on some
/// platforms), converts it to PNG natively first.
Future<ui.Image> _decodeAt(
  Uint8List bytes,
  int index,
  int width,
  int height,
) async {
  try {
    return await _decode(bytes, width, height);
  } catch (_) {
    if (kIsWeb) {
      throw PixelCompressError(
        'Source $index is not a decodable image.',
        code: 'decode_failed',
      );
    }
  }
  try {
    final png = await PixelImageCompressor.compressBytes(
      bytes,
      minWidth: width,
      minHeight: height,
      format: PixelImageFormat.png,
    );
    return await _decode(png, width, height);
  } catch (e) {
    throw PixelCompressError(
      'Source $index is not a decodable image: $e',
      code: 'decode_failed',
    );
  }
}

Future<ui.Image> _decode(Uint8List bytes, int width, int height) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _encode(ui.Image image, PixelMergeOptions options) async {
  final ByteData? png;
  try {
    png = await image.toByteData(format: ui.ImageByteFormat.png);
  } catch (e) {
    throw PixelCompressError('PNG encoding failed: $e', code: 'encode_failed');
  }
  if (png == null) {
    throw PixelCompressError('PNG encoding failed.', code: 'encode_failed');
  }
  final pngBytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  if (options.format == .png) return pngBytes;
  try {
    // Min bounds equal to the canvas: no further scaling, just re-encoding.
    return await PixelImageCompressor.compressBytes(
      pngBytes,
      minWidth: image.width,
      minHeight: image.height,
      quality: options.quality,
      format: options.format,
    );
  } on PixelCompressError {
    rethrow;
  } on UnsupportedError catch (e) {
    throw PixelCompressError('${e.message}', code: 'unsupported_format');
  } catch (e) {
    throw PixelCompressError(
      'Encoding to ${options.format.name} failed: $e',
      code: 'encode_failed',
    );
  }
}
