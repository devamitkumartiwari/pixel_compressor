import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/merge/image_merger.dart' show renderMerge;
import 'package:pixel_compressor/src/merge/merge_geometry.dart';

Future<Uint8List> _png(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<(int, int)> _size(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final size = (image.width, image.height);
  image.dispose();
  codec.dispose();
  return size;
}

Future<ui.Color> _pixel(Uint8List bytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  final color = ui.Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
  image.dispose();
  return color;
}

const _red = ui.Color(0xFFFF0000);
const _blue = ui.Color(0xFF0000FF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeMergeLayout', () {
    MergeLayoutResult layout(
      List<(double, double)> sizes,
      PixelMergeOptions o,
    ) => computeMergeLayout(
      sizes: [for (final (w, h) in sizes) (width: w, height: h)],
      options: o,
    );

    test('vertical scaleToFit matches the widest width', () {
      final r = layout([(100, 50), (200, 100)], const PixelMergeOptions());
      expect((r.width, r.height), (200.0, 200.0));
      expect(r.placements[0], (dx: 0.0, dy: 0.0, width: 200.0, height: 100.0));
      expect(r.placements[1].dy, 100.0);
    });

    test('horizontal with spacing', () {
      final r = layout([
        (100, 100),
        (50, 100),
      ], const PixelMergeOptions(layout: .horizontal, spacing: 10));
      expect((r.width, r.height), (160.0, 100.0));
      expect(r.placements[1].dx, 110.0);
    });

    test('no scaleToFit centres narrower images', () {
      final r = layout([
        (100, 10),
        (50, 10),
      ], const PixelMergeOptions(scaleToFit: false));
      expect(r.placements[1].dx, 25.0);
    });

    test('grid justifies full rows to the same width', () {
      final r = layout([
        (100, 100),
        (200, 100),
        (100, 50),
        (100, 100),
        (300, 300),
      ], const PixelMergeOptions(layout: .grid, gridColumns: 2));
      // Rows 0 and 1 span the full width; the short last row is centred.
      double right(int i) => r.placements[i].dx + r.placements[i].width;
      expect(right(1), closeTo(r.width, 1e-6));
      expect(right(3), closeTo(r.width, 1e-6));
      expect(r.placements[4].dx, greaterThan(0));
      // Every placement stays inside the canvas.
      for (final p in r.placements) {
        expect(p.dx + p.width, lessThanOrEqualTo(r.width + 1e-6));
        expect(p.dy + p.height, lessThanOrEqualTo(r.height + 1e-6));
      }
    });

    test('defaults clamp the long side to 4096', () {
      final r = layout([(3000, 4000), (3000, 4000)], const PixelMergeOptions());
      expect(r.height, closeTo(4096, 1e-6));
      expect(r.width, closeTo(1536, 1e-6));
    });

    test('hard limits apply even with huge explicit bounds', () {
      final r = layout(
        [(10000, 100), (10000, 100)],
        const PixelMergeOptions(
          layout: .horizontal,
          maxOutputWidth: 100000,
          maxOutputHeight: 100000,
        ),
      );
      expect(r.width, lessThanOrEqualTo(kMergeMaxSide + 1e-6));
      expect(r.width * r.height, lessThanOrEqualTo(kMergeMaxPixels + 1));
    });
  });

  group('PixelImageMerger.merge', () {
    testWidgets('vertical PNG merge has the expected size and pixels', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final result = await PixelImageMerger.merge([
          PixelMergeSource.bytes(await _png(100, 50, _red)),
          PixelMergeSource.bytes(await _png(100, 50, _blue)),
        ]);
        expect((result.width, result.height), (100, 100));
        expect(await _size(result.bytes), (100, 100));
        expect(await _pixel(result.bytes, 50, 10), _red);
        expect(await _pixel(result.bytes, 50, 90), _blue);
        expect(result.sourceCount, 2);
      });
    });

    testWidgets('huge inputs are clamped instead of failing', (tester) async {
      await tester.runAsync(() async {
        final wide = await _png(10000, 100, _red);
        final result = await PixelImageMerger.merge(
          [PixelMergeSource.bytes(wide), PixelMergeSource.bytes(wide)],
          options: const PixelMergeOptions(
            layout: .horizontal,
            maxOutputWidth: 50000,
            maxOutputHeight: 50000,
          ),
        );
        expect(result.width, lessThanOrEqualTo(kMergeMaxSide));
      });
    });

    testWidgets('transparent background turns white for JPEG layouts', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // scaleToFit: false leaves a gap next to the narrow image.
        final image = await renderMerge(
          [
            PixelMergeSource.bytes(await _png(100, 20, _red)),
            PixelMergeSource.bytes(await _png(20, 20, _blue)),
          ],
          const PixelMergeOptions(
            scaleToFit: false,
            alignment: .start,
            background: ui.Color(0x00000000),
            format: .jpeg,
          ),
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        expect(
          await _pixel(png!.buffer.asUint8List(), 80, 30),
          const ui.Color(0xFFFFFFFF),
        );
      });
    });

    testWidgets('errors name the offending source', (tester) async {
      await tester.runAsync(() async {
        final good = await _png(10, 10, _red);
        await expectLater(
          PixelImageMerger.merge([
            PixelMergeSource.bytes(good),
            PixelMergeSource.bytes(Uint8List.fromList(List.filled(64, 7))),
          ]),
          throwsA(
            isA<PixelCompressError>()
                .having((e) => e.code, 'code', 'decode_failed')
                .having((e) => e.message, 'message', contains('Source 1')),
          ),
        );
        await expectLater(
          PixelImageMerger.merge([PixelMergeSource.bytes(good)]),
          throwsA(
            isA<PixelCompressError>().having(
              (e) => e.code,
              'code',
              'invalid_input',
            ),
          ),
        );
        await expectLater(
          PixelImageMerger.merge([
            PixelMergeSource.bytes(good),
            PixelMergeSource.bytes(Uint8List(0)),
          ]),
          throwsA(
            isA<PixelCompressError>().having(
              (e) => e.code,
              'code',
              'invalid_input',
            ),
          ),
        );
        await expectLater(
          PixelImageMerger.merge([
            PixelMergeSource.bytes(good),
            const PixelMergeSource.file('/definitely/missing.png'),
          ]),
          throwsA(
            isA<PixelCompressError>().having(
              (e) => e.code,
              'code',
              'io_failed',
            ),
          ),
        );
      });
    });

    testWidgets('file sources and outputPath', (tester) async {
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('pc_merge');
        final a = File('${dir.path}/a.png')
          ..writeAsBytesSync(await _png(40, 40, _red));
        final b = File('${dir.path}/b.png')
          ..writeAsBytesSync(await _png(40, 40, _blue));
        final out = '${dir.path}/nested/out.png';
        final result = await PixelImageMerger.merge([
          PixelMergeSource.file(a.path),
          PixelMergeSource.file(b.path),
        ], options: PixelMergeOptions(layout: .grid, outputPath: out));
        expect(result.path, out);
        expect(File(out).readAsBytesSync(), result.bytes);
        expect((result.width, result.height), (80, 40));
        dir.deleteSync(recursive: true);
      });
    });
  });

  group('PixelMergeView', () {
    testWidgets('renders a preview and capture matches the headless merge', (
      tester,
    ) async {
      final sources = await tester.runAsync(
        () async => [
          PixelMergeSource.bytes(await _png(60, 30, _red)),
          PixelMergeSource.bytes(await _png(60, 30, _blue)),
        ],
      );
      final controller = PixelMergeCaptureController();
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: PixelMergeView(sources: sources!, controller: controller),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsOneWidget);
      expect(controller.isAttached, isTrue);

      final captured = await tester.runAsync(() => controller.capture());
      final direct = await tester.runAsync(
        () => PixelImageMerger.merge(sources),
      );
      expect(captured!.bytes, direct!.bytes);

      await tester.pumpWidget(const SizedBox());
      expect(controller.isAttached, isFalse);
    });
  });
}
