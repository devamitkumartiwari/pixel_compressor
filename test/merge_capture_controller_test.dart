import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

Future<ui.Image> _solidImage(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  test('capturePng throws InvalidMediaException when unattached', () async {
    final controller = MergeCaptureController();
    expect(
      () => controller.capturePng(),
      throwsA(isA<InvalidMediaException>()),
    );
  });

  testWidgets('capturePng returns PNG bytes for a rendered MergeView', (
    tester,
  ) async {
    // testWidgets runs inside a fake-async zone, where real engine
    // rasterization (picture.toImage / RenderRepaintBoundary.toImage)
    // never resolves — both stages need runAsync to escape it.
    late List<ui.Image> images;
    await tester.runAsync(() async {
      images = [
        await _solidImage(20, 10, const ui.Color(0xFFFF0000)),
        await _solidImage(20, 10, const ui.Color(0xFF0000FF)),
      ];
    });
    final controller = MergeCaptureController();
    addTearDown(() {
      for (final image in images) {
        image.dispose();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MergeView(images: images, controller: controller),
      ),
    );
    await tester.pump();

    late Uint8List png;
    await tester.runAsync(() async {
      png = await controller.capturePng();
    });
    expect(png, isNotEmpty);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
