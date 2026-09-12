import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/cancellation_token.dart';
import 'package:pixel_compressor/src/core/image_engine_dart.dart';

Uint8List _solidPng(int width, int height, {int? exifOrientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 50, 50));
  if (exifOrientation != null) {
    image.exif.imageIfd.orientation = exifOrientation;
  }
  return exifOrientation != null ? img.encodeJpg(image) : img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = ImageEngineDart();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pixel_compressor_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'compresses a plain PNG with no options unchanged in dimensions',
    () async {
      final source = _solidPng(100, 50);
      final outputPath = '${tempDir.path}/out.png';

      final result = await engine.compress(
        taskId: 't1',
        sourceBytes: source,
        format: ImageFormat.png,
        options: const ImageCompressOptions(),
        outputPath: outputPath,
      );

      expect(File(outputPath).existsSync(), isTrue);
      expect(result.format, 'png');
      final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
      expect(result.originalSizeBytes, source.lengthInBytes);
      expect(result.outputSizeBytes, File(outputPath).lengthSync());
    },
  );

  test(
    'fits to maxWidth/maxHeight preserving aspect, never upscaling',
    () async {
      final source = _solidPng(200, 100);
      final outputPath = '${tempDir.path}/out.png';

      await engine.compress(
        taskId: 't2',
        sourceBytes: source,
        format: ImageFormat.png,
        options: const ImageCompressOptions(maxWidth: 100, maxHeight: 100),
        outputPath: outputPath,
      );

      final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);

      // A max bound larger than the source must not upscale.
      final outputPath2 = '${tempDir.path}/out2.png';
      await engine.compress(
        taskId: 't2b',
        sourceBytes: source,
        format: ImageFormat.png,
        options: const ImageCompressOptions(maxWidth: 1000, maxHeight: 1000),
        outputPath: outputPath2,
      );
      final decoded2 = img.decodeImage(File(outputPath2).readAsBytesSync())!;
      expect(decoded2.width, 200);
      expect(decoded2.height, 100);
    },
  );

  test('rotationDegrees=90/270 swaps output dimensions', () async {
    final source = _solidPng(200, 100);

    for (final degrees in [90, 270]) {
      final outputPath = '${tempDir.path}/out_$degrees.png';
      await engine.compress(
        taskId: 't3_$degrees',
        sourceBytes: source,
        format: ImageFormat.png,
        options: ImageCompressOptions(rotationDegrees: degrees),
        outputPath: outputPath,
      );
      final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(decoded.width, 100, reason: 'degrees=$degrees');
      expect(decoded.height, 200, reason: 'degrees=$degrees');
    }
  });

  test('rotationDegrees=180 keeps dimensions', () async {
    final source = _solidPng(200, 100);
    final outputPath = '${tempDir.path}/out180.png';
    await engine.compress(
      taskId: 't4',
      sourceBytes: source,
      format: ImageFormat.png,
      options: const ImageCompressOptions(rotationDegrees: 180),
      outputPath: outputPath,
    );
    final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
    expect(decoded.width, 200);
    expect(decoded.height, 100);
  });

  test(
    'EXIF autoCorrectOrientation=true bakes a 90-degree source rotation',
    () async {
      final source = _solidPng(200, 100, exifOrientation: 6); // ROTATE_90
      final outputPath = '${tempDir.path}/out_exif.jpg';

      await engine.compress(
        taskId: 't6',
        sourceBytes: source,
        format: ImageFormat.jpeg,
        options: const ImageCompressOptions(),
        outputPath: outputPath,
      );

      final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(decoded.width, 100);
      expect(decoded.height, 200);
    },
  );

  test('EXIF autoCorrectOrientation=false leaves pixels unrotated', () async {
    final source = _solidPng(200, 100, exifOrientation: 6); // ROTATE_90
    final outputPath = '${tempDir.path}/out_exif_off.jpg';

    await engine.compress(
      taskId: 't7',
      sourceBytes: source,
      format: ImageFormat.jpeg,
      options: const ImageCompressOptions(autoCorrectOrientation: false),
      outputPath: outputPath,
    );

    final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
    expect(decoded.width, 200);
    expect(decoded.height, 100);
  });

  test(
    'ExifPolicy.strip removes EXIF from a JPEG with GPS-like data',
    () async {
      final image = img.Image(width: 20, height: 20);
      img.fill(image, color: img.ColorRgb8(1, 2, 3));
      image.exif.imageIfd.orientation = 1;
      image.exif.gpsIfd.gpsLatitude = 12.34;
      final source = img.encodeJpg(image);
      final outputPath = '${tempDir.path}/stripped.jpg';

      await engine.compress(
        taskId: 't8',
        sourceBytes: source,
        format: ImageFormat.jpeg,
        options: const ImageCompressOptions(),
        outputPath: outputPath,
      );

      final decoded = img.decodeImage(File(outputPath).readAsBytesSync())!;
      expect(decoded.exif.isEmpty, isTrue);
    },
  );

  test('throws UnsupportedMediaException for undecodable bytes', () async {
    await expectLater(
      engine.compress(
        taskId: 't9',
        sourceBytes: Uint8List.fromList([1, 2, 3, 4]),
        format: ImageFormat.jpeg,
        options: const ImageCompressOptions(),
        outputPath: '${tempDir.path}/never.jpg',
      ),
      throwsA(isA<UnsupportedMediaException>()),
    );
  });

  test('targetSizeBytes converges to at or under the requested size', () async {
    // A large, detailed-ish image so JPEG quality actually affects size.
    final image = img.Image(width: 400, height: 400);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x ^ y) % 256);
      }
    }
    final source = img.encodeJpg(image, quality: 100);
    final outputPath = '${tempDir.path}/target.jpg';

    final result = await engine.compress(
      taskId: 't10',
      sourceBytes: source,
      format: ImageFormat.jpeg,
      options: ImageCompressOptions(targetSizeBytes: source.lengthInBytes ~/ 4),
      outputPath: outputPath,
    );

    expect(
      result.outputSizeBytes,
      lessThanOrEqualTo(source.lengthInBytes ~/ 4),
    );
  });

  test('a cancelled token stops a compress mid target-size loop, no output written', () async {
    final image = img.Image(width: 400, height: 400);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x ^ y) % 256);
      }
    }
    final source = img.encodeJpg(image, quality: 100);
    final outputPath = '${tempDir.path}/cancelled.jpg';
    const taskId = 'cancel-mid-loop';

    final token = CancellationToken();
    var encodingAttempts = 0;
    final subscription = PixelCompressor.progressStream
        .where(
          (e) =>
              e.taskId == taskId &&
              e.stage == CompressionStage.encoding &&
              e.note != null,
        )
        .listen((_) {
          encodingAttempts++;
          if (encodingAttempts == 2) {
            token.cancel();
          }
        });

    await expectLater(
      engine.compress(
        taskId: taskId,
        sourceBytes: source,
        format: ImageFormat.jpeg,
        // Deliberately unachievable within a couple of attempts (noisy
        // image data compresses poorly) so cancellation has time to land
        // before the loop would otherwise finish on its own.
        options: ImageCompressOptions(
          targetSizeBytes: source.lengthInBytes ~/ 100,
        ),
        outputPath: outputPath,
        cancellationToken: token,
      ),
      throwsA(isA<CompressionCancelledException>()),
    );

    await subscription.cancel();
    expect(encodingAttempts, greaterThanOrEqualTo(2));
    expect(File(outputPath).existsSync(), isFalse);
  });
}
