import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

Future<File> _writeSolidPng(
  String path,
  int width,
  int height,
  ui.Color color,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.writeAsBytes(byteData!.buffer.asUint8List());
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pixel_compressor_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ImageMerger.combine', () {
    test('throws InvalidMediaException for an empty list', () async {
      expect(
        () => PixelCompressor.merge.combine(const []),
        throwsA(
          isA<InvalidMediaException>().having(
            (e) => e.nativeCode,
            'nativeCode',
            'invalid_media',
          ),
        ),
      );
    });

    test('throws InvalidMediaException for a single-image list', () async {
      final file = await _writeSolidPng(
        '${tempDir.path}/a.png',
        10,
        10,
        const ui.Color(0xFFFF0000),
      );
      expect(
        () => PixelCompressor.merge.combine([MediaSource.file(file)]),
        throwsA(isA<InvalidMediaException>()),
      );
    });

    test('throws InvalidMediaException for a nonexistent path', () async {
      expect(
        () => PixelCompressor.merge.combine([
          MediaSource.path('${tempDir.path}/does_not_exist.png'),
          MediaSource.path('${tempDir.path}/also_missing.png'),
        ]),
        throwsA(isA<InvalidMediaException>()),
      );
    });

    test('throws DecodingException for unreadable image bytes', () async {
      final garbage = File('${tempDir.path}/garbage.png');
      await garbage.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));
      final good = await _writeSolidPng(
        '${tempDir.path}/good.png',
        10,
        10,
        const ui.Color(0xFF00FF00),
      );

      expect(
        () => PixelCompressor.merge.combine([
          MediaSource.file(garbage),
          MediaSource.file(good),
        ]),
        throwsA(
          isA<DecodingException>().having(
            (e) => e.nativeCode,
            'nativeCode',
            'decoding_error',
          ),
        ),
      );
    });

    test('merges two images vertically and writes a PNG', () async {
      final a = await _writeSolidPng(
        '${tempDir.path}/a.png',
        20,
        10,
        const ui.Color(0xFFFF0000),
      );
      final b = await _writeSolidPng(
        '${tempDir.path}/b.png',
        20,
        10,
        const ui.Color(0xFF0000FF),
      );

      final result = await PixelCompressor.merge.combine([
        MediaSource.file(a),
        MediaSource.file(b),
      ], options: const MergeOptions(direction: MergeDirection.vertical));

      expect(result.width, 20);
      expect(result.height, 20);
      expect(result.sourceCount, 2);
      expect(result.outputFile.existsSync(), isTrue);

      // PNG magic number.
      expect(result.outputBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

      final codec = await ui.instantiateImageCodec(result.outputBytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 20);
      expect(frame.image.height, 20);
      frame.image.dispose();
    });

    test('honors an explicit outputPath', () async {
      final a = await _writeSolidPng(
        '${tempDir.path}/a.png',
        10,
        10,
        const ui.Color(0xFFFF0000),
      );
      final b = await _writeSolidPng(
        '${tempDir.path}/b.png',
        10,
        10,
        const ui.Color(0xFF00FF00),
      );
      final outputPath = '${tempDir.path}/merged_output.png';

      final result = await PixelCompressor.merge.combine([
        MediaSource.file(a),
        MediaSource.file(b),
      ], options: MergeOptions(outputPath: outputPath));

      expect(result.outputPath, outputPath);
      expect(File(outputPath).existsSync(), isTrue);
    });
  });
}
