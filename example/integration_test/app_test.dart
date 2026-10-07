// End-to-end run of the example on a real device/desktop: drives every tab
// with the bundled samples (real native compression), and saves screenshots.
//
//   flutter test integration_test -d macos   (or an iOS/Android device)
import 'dart:async';
import 'dart:io';

import 'package:example/main.dart';
import 'package:example/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final _root = GlobalKey();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final shotsDir = Directory(
    '${Directory.systemTemp.path}/pixel_compressor_shots',
  );

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      final boundary =
          _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: .png);
      await shotsDir.create(recursive: true);
      await File('${shotsDir.path}/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });
  }

  /// Pumps real frames until [finder] matches (native calls take real time).
  ///
  /// With [scroll], also scrolls the page down while waiting: results are
  /// appended below the options, and on the short phone layout they are
  /// outside the list's build area until scrolled to.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
    bool scroll = false,
  }) async {
    final pages = find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == .down)
        .hitTestable();
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
      if (scroll) {
        // Move the scroll position directly: a simulated drag could land on
        // a control and change state.
        for (final page in pages.evaluate()) {
          final position =
              ((page as StatefulElement).state as ScrollableState).position;
          if (position.pixels < position.maxScrollExtent) {
            position.jumpTo(
              (position.pixels + 200).clamp(0, position.maxScrollExtent),
            );
          }
        }
      }
    }
    final onScreen = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .nonNulls
        .join(' | ');
    throw TimeoutException(
      'Timed out waiting for $finder. On screen: $onScreen',
    );
  }

  /// Scrolls [finder] into view (the phone layout is shorter than its
  /// content), then taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    // ensureVisible also aligns the tab PageView, which can snap to the next
    // tab, so only scroll when the target can't be hit where it is.
    if (finder.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(finder);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    final tab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text(label),
    );
    await tapVisible(tester, tab);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> launch(WidgetTester tester, Size size, double dpr) async {
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(key: _root, child: const PixelCompressorExampleApp()),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('phone layout: every tab with samples', (tester) async {
    await launch(tester, const Size(390, 600), 2);
    await shot(tester, '01_image_empty');

    // Image: compress the landscape sample (compressAsset).
    await tapVisible(tester, find.text('Add image'));
    await waitFor(tester, find.text('Landscape'));
    await shot(tester, '02_source_sheet');
    await tapVisible(tester, find.text('Landscape'));
    await waitFor(tester, find.text('Compress'));
    await shot(tester, '03_image_source');
    await tapVisible(tester, find.text('Compress'));
    await waitFor(tester, find.text('Compressed'), scroll: true);
    await tester.ensureVisible(find.byType(SavingsBadge));
    await shot(tester, '04_image_result');

    // Batch: all samples.
    await openTab(tester, 'Batch');
    await tapVisible(tester, find.text('Add images'));
    await waitFor(tester, find.text('Use all'));
    await tapVisible(tester, find.text('Use all'));
    await waitFor(tester, find.textContaining('Compress 3'));
    await tapVisible(tester, find.textContaining('Compress 3'));
    await waitFor(tester, find.textContaining('compressed'), scroll: true);
    await tester.ensureVisible(find.textContaining('compressed').first);
    await shot(tester, '05_batch_result');

    // Inspect: the EXIF-6 portrait.
    await openTab(tester, 'Inspect');
    await tapVisible(tester, find.text('Pick').first);
    await waitFor(tester, find.text('Portrait (EXIF 6)'));
    await tapVisible(tester, find.text('Portrait (EXIF 6)'));
    await waitFor(tester, find.text('Displayed size'), scroll: true);
    await shot(tester, '06_inspect');

    // Merge: live view, then headless merge.
    await openTab(tester, 'Merge');
    await tapVisible(tester, find.text('Add images'));
    await waitFor(tester, find.text('Use all'));
    await tapVisible(tester, find.text('Use all'));
    await waitFor(tester, find.byType(RawImage));
    await shot(tester, '07_merge_preview');
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(BusyButton),
        matching: find.text('Merge'),
      ),
    );
    await waitFor(tester, find.textContaining('Merged 3'), scroll: true);
    await tester.ensureVisible(find.textContaining('Merged 3'));
    await shot(tester, '08_merge_result');

    // Tools.
    await openTab(tester, 'Tools');
    await waitFor(tester, find.text('JPEG'));
    await shot(tester, '09_tools');

    // Video tab empty state, then dark mode.
    await openTab(tester, 'Video');
    await shot(tester, '10_video_empty');
    await tester.tap(find.byTooltip('Theme: System'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Theme: Light'));
    await tester.pump(const Duration(milliseconds: 600));
    await openTab(tester, 'Image');
    await shot(tester, '11_image_result_dark');

    // ignore: avoid_print
    print('Screenshots: ${shotsDir.path}');
  });

  testWidgets('wide layout: two panes', (tester) async {
    await launch(tester, const Size(1000, 600), 1.5);
    await tapVisible(tester, find.text('Add image'));
    await waitFor(tester, find.text('Portrait (EXIF 6)'));
    await tapVisible(tester, find.text('Portrait (EXIF 6)'));
    await waitFor(tester, find.text('Compress'));
    await tapVisible(tester, find.text('Compress'));
    await waitFor(tester, find.text('Compressed'), scroll: true);
    await shot(tester, '12_wide_image');

    await openTab(tester, 'Merge');
    await tapVisible(tester, find.text('Add images'));
    await waitFor(tester, find.text('Use all'));
    await tapVisible(tester, find.text('Use all'));
    await waitFor(tester, find.byType(RawImage));
    await shot(tester, '13_wide_merge');
  });
}
