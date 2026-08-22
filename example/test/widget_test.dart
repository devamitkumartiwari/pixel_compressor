import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('app launches on the image compression page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PixelCompressorExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('pixel_compressor — Image'), findsOneWidget);
    expect(find.text('Pick an image'), findsOneWidget);
  });

  testWidgets('drawer navigates to the capabilities page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PixelCompressorExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capabilities'));
    await tester.pumpAndSettle();

    expect(find.text('pixel_compressor — Capabilities'), findsOneWidget);
    expect(find.text('Check capabilities'), findsOneWidget);
  });
}
