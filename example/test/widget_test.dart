import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const PixelCompressorExampleApp());
    await tester.pumpAndSettle();
  }

  testWidgets('launches on the Image tab with its empty state', (tester) async {
    await launch(tester);

    expect(find.text('pixel_compressor'), findsOneWidget);
    expect(find.text('Pick an image to compress'), findsOneWidget);
    expect(find.text('Add image'), findsOneWidget);
  });

  // Tab label → text that only that tab's page shows.
  const pages = {
    'Batch': 'Pick a few images',
    'Inspect': 'IMAGE HEADER · PIXELIMAGEINFO',
    'Video': 'Pick a video to compress',
    'Thumbnails': 'Pick a video',
    'Merge': 'Combine images',
    'Tools': 'VALIDATOR',
  };

  for (final MapEntry(key: tab, value: marker) in pages.entries) {
    testWidgets('$tab tab is reachable', (tester) async {
      await launch(tester);

      final tabFinder = find.descendant(
        of: find.byType(TabBar),
        matching: find.text(tab),
      );
      await tester.ensureVisible(tabFinder);
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();

      expect(find.text(marker), findsOneWidget);
    });
  }

  testWidgets('theme toggle cycles system → light → dark', (tester) async {
    await launch(tester);

    MaterialApp app() => tester.widget(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    await tester.tap(find.byTooltip('Theme: System'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);

    await tester.tap(find.byTooltip('Theme: Light'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
  });
}
