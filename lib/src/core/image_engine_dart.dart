import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../platform/progress_hub.dart';
import 'cancellation_token.dart';
import 'enums/compression_stage.dart';
import 'enums/exif_policy.dart';
import 'enums/image_format.dart';
import 'exceptions/pixel_compressor_exception.dart';
import 'jpeg_orientation_reader.dart';
import 'models/compression_result.dart';
import 'models/image_compress_options.dart';
import 'models/progress_event.dart';
import 'target_size_loop.dart';

/// Pure-Dart JPEG/PNG compression pipeline (`package:image`), a direct
/// port of `ImageEngine.kt`/`ImageEngine.swift`'s pipeline: decode →
/// combine EXIF orientation with requested rotation → rotate → resize →
/// encode → EXIF keep/strip → optional target-size search. WebP and HEIC
/// have no pure-Dart encoder anywhere and are never routed here — see
/// `image_backend_io.dart`.
///
/// Known limitation vs. the native engines: runs on the calling isolate
/// (not a background isolate), so a very large image may briefly jank the
/// UI thread — matching `ImageMerger`'s existing pure-Dart behavior today,
/// but unlike the native path, which already runs off the main thread.
///
/// [cancellationToken], if given, is checked at the same stage boundaries
/// the native engines check `ensureActive()`/`isCancelled()` at — this is
/// cooperative, not preemptive, so cancellation takes effect at the next
/// checkpoint, not instantly.
class ImageEngineDart {
  const ImageEngineDart();

  Future<CompressionResult> compress({
    required String taskId,
    required Uint8List sourceBytes,
    required ImageFormat format,
    required ImageCompressOptions options,
    required String outputPath,
    CancellationToken? cancellationToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    _report(taskId, CompressionStage.preparing, 0);
    cancellationToken?.throwIfCancelled(taskId);

    _report(taskId, CompressionStage.analyzing, 5);
    // decodeImage can throw (not just return null) on bytes that partially
    // match a format's signature check but aren't fully valid (observed
    // with package:image's PSD sniffing on arbitrary short byte strings) —
    // treat any decode failure, thrown or null, as an unsupported source.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(sourceBytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw UnsupportedMediaException(
        nativeCode: 'unsupported_media',
        nativeMessage: 'Source is not a decodable JPEG/PNG image.',
        taskId: taskId,
      );
    }
    final img.Image decodedImage = decoded;

    // package:image's own JPEG decode unconditionally bakes the EXIF
    // orientation into the decoded pixels and clears the tag on the
    // returned Image (see getImageFromJpeg in its source) — there is no
    // decode-time opt-out. So `decoded` already reflects a `bakedDegrees`
    // rotation regardless of `autoCorrectOrientation`, and the *original*
    // tag value has to be read independently, before decode, to know what
    // that was. `readRawJpegOrientation` returns null for PNG (which
    // package:image's PNG decoder never auto-rotates) or a JPEG with no
    // orientation tag, in which case bakedDegrees is 0 and decode didn't
    // change anything.
    final rawOrientation = readRawJpegOrientation(sourceBytes);
    final bakedDegrees = _orientationToDegrees(rawOrientation);
    final requestedDegrees = _requireCardinal(taskId, options.rotationDegrees);
    // The rotation still needed on top of `decoded` to reach the correct
    // final result: if auto-correcting, package:image already applied the
    // source correction, so only the caller's own extra request remains;
    // if not, undo the forced bake first, then apply the caller's request
    // — rotations compose by simple addition, so this reaches the exact
    // same total as native's single combined rotation either way.
    final totalRotation = options.autoCorrectOrientation
        ? requestedDegrees
        : (requestedDegrees - bakedDegrees + 360) % 360;

    cancellationToken?.throwIfCancelled(taskId);
    _report(taskId, CompressionStage.decoding, 10);

    final Uint8List encodedBytes;
    if (options.targetSizeBytes != null) {
      encodedBytes = await runTargetSizeLoop(
        targetSizeBytes: options.targetSizeBytes!,
        attempt: (quality, maxLongestEdge) async {
          cancellationToken?.throwIfCancelled(taskId);
          final processed = _rotateFit(
            decodedImage,
            totalRotation: totalRotation,
            maxWidth: maxLongestEdge ?? options.maxWidth,
            maxHeight: maxLongestEdge ?? options.maxHeight,
          );
          final bytes = _encode(
            processed,
            format,
            quality,
            options.exifPolicy,
            decodedImage.exif,
          );
          return TargetSizeAttempt(
            bytes: bytes,
            longestEdge: max(processed.width, processed.height),
          );
        },
        onAttempt: (attemptNumber, maxAttempts, note) {
          final percent = 10 + (attemptNumber / maxAttempts) * 80;
          _report(taskId, CompressionStage.encoding, percent, note: note);
        },
      );
    } else {
      cancellationToken?.throwIfCancelled(taskId);
      final processed = _rotateFit(
        decodedImage,
        totalRotation: totalRotation,
        maxWidth: options.maxWidth,
        maxHeight: options.maxHeight,
      );
      _report(taskId, CompressionStage.encoding, 50);
      final clampedQuality = options.quality.clamp(1, 100);
      encodedBytes = _encode(
        processed,
        format,
        clampedQuality,
        options.exifPolicy,
        decodedImage.exif,
      );
    }

    cancellationToken?.throwIfCancelled(taskId);
    _report(taskId, CompressionStage.finalizing, 95);
    final outputFile = File(outputPath);
    try {
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(encodedBytes, flush: true);
    } on FileSystemException catch (e) {
      throw _mapWriteError(e, taskId);
    }

    final originalSizeBytes = sourceBytes.lengthInBytes;
    final outputSizeBytes = encodedBytes.lengthInBytes;
    final ratio = originalSizeBytes > 0
        ? outputSizeBytes / originalSizeBytes
        : 0.0;
    final formatName = format.name;

    stopwatch.stop();
    _report(taskId, CompressionStage.completed, 100);

    return CompressionResult(
      outputPath: outputPath,
      originalSizeBytes: originalSizeBytes,
      outputSizeBytes: outputSizeBytes,
      compressionRatio: ratio,
      duration: stopwatch.elapsed,
      codec: formatName,
      format: formatName,
    );
  }

  img.Image _rotateFit(
    img.Image source, {
    required int totalRotation,
    int? maxWidth,
    int? maxHeight,
  }) {
    var image = img.copyRotate(source, angle: totalRotation);
    if (maxWidth == null && maxHeight == null) return image;

    final widthScale = maxWidth != null
        ? maxWidth / image.width
        : double.maxFinite;
    final heightScale = maxHeight != null
        ? maxHeight / image.height
        : double.maxFinite;
    final scale = [widthScale, heightScale, 1.0].reduce(min);
    if (scale >= 1.0) return image;

    final newWidth = max(1, (image.width * scale).round());
    final newHeight = max(1, (image.height * scale).round());
    image = img.copyResize(image, width: newWidth, height: newHeight);
    return image;
  }

  Uint8List _encode(
    img.Image image,
    ImageFormat format,
    int quality,
    ExifPolicy exifPolicy,
    img.ExifData sourceExif,
  ) {
    switch (exifPolicy) {
      case ExifPolicy.strip:
        image.exif = img.ExifData();
      case ExifPolicy.keep:
        final exif = img.ExifData.from(sourceExif);
        exif.imageIfd.orientation = 1;
        image.exif = exif;
    }

    switch (format) {
      case ImageFormat.jpeg:
        return img.encodeJpg(image, quality: quality.clamp(1, 100));
      case ImageFormat.png:
        return img.encodePng(image);
      case ImageFormat.webp:
      case ImageFormat.heic:
        throw StateError('ImageEngineDart only handles jpeg/png; got $format');
    }
  }

  /// Maps an EXIF orientation tag value (1-8) to a cardinal rotation in
  /// degrees, collapsing mirrored variants to their non-flipped rotation —
  /// this plugin never mirrors pixels, only rotates, matching
  /// `ExifSupport.kt`'s `ORIENTATION_TO_DEGREES` table exactly.
  int _orientationToDegrees(int? exifOrientation) => switch (exifOrientation) {
    3 || 4 => 180,
    5 || 6 => 90,
    7 || 8 => 270,
    _ => 0, // 1 (normal), 2 (flip-horizontal), null, or unrecognized
  };

  int _requireCardinal(String taskId, int requestedDegrees) {
    if (requestedDegrees != 0 &&
        requestedDegrees != 90 &&
        requestedDegrees != 180 &&
        requestedDegrees != 270) {
      throw InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'rotationDegrees must be one of 0, 90, 180, 270, got $requestedDegrees',
        taskId: taskId,
      );
    }
    return requestedDegrees;
  }

  PixelCompressorException _mapWriteError(
    FileSystemException e,
    String taskId,
  ) {
    if (e.osError?.errorCode == 28) {
      return InsufficientStorageException(
        nativeCode: 'insufficient_storage',
        nativeMessage: 'No space left to write output file: ${e.message}',
        taskId: taskId,
      );
    }
    return EncodingException(
      nativeCode: 'encoding_error',
      nativeMessage: 'Failed to write output file: ${e.message}',
      taskId: taskId,
    );
  }

  void _report(
    String taskId,
    CompressionStage stage,
    num percent, {
    String? note,
  }) {
    ProgressHub.instance.emit(
      ProgressEvent(
        taskId: taskId,
        stage: stage,
        percent: percent.toDouble(),
        note: note,
      ),
    );
  }
}
