import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/src/core/enums/merge_alignment.dart';
import 'package:pixel_compressor/src/core/enums/merge_direction.dart';
import 'package:pixel_compressor/src/core/merge_geometry.dart';

void main() {
  group('computeMergeCanvasSize', () {
    test('vertical + scaleToFit true: width is widest source', () {
      final size = computeMergeCanvasSize(
        sizes: [(width: 100, height: 50), (width: 200, height: 100)],
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: true,
      );
      // Both images scaled to width 200: heights become 100 and 100.
      expect(size.width, 200);
      expect(size.height, 200);
    });

    test('horizontal + scaleToFit true: height is tallest source', () {
      final size = computeMergeCanvasSize(
        sizes: [(width: 100, height: 50), (width: 100, height: 100)],
        direction: MergeDirection.horizontal,
        spacing: 0,
        scaleToFit: true,
      );
      // Both images scaled to height 100: widths become 200 and 100.
      expect(size.height, 100);
      expect(size.width, 300);
    });

    test('scaleToFit false: cross axis is widest/tallest native size', () {
      final size = computeMergeCanvasSize(
        sizes: [(width: 50, height: 40), (width: 80, height: 20)],
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: false,
      );
      expect(size.width, 80);
      expect(size.height, 60);
    });

    test('spacing only affects the main-axis total', () {
      final withoutSpacing = computeMergeCanvasSize(
        sizes: [(width: 10, height: 10), (width: 10, height: 10)],
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: true,
      );
      final withSpacing = computeMergeCanvasSize(
        sizes: [(width: 10, height: 10), (width: 10, height: 10)],
        direction: MergeDirection.vertical,
        spacing: 5,
        scaleToFit: true,
      );
      expect(withSpacing.width, withoutSpacing.width);
      expect(withSpacing.height, withoutSpacing.height + 5);
    });
  });

  group('computeMergePlacements', () {
    test('returns empty list for empty sizes', () {
      final placements = computeMergePlacements(
        sizes: const [],
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: true,
        alignment: MergeAlignment.center,
      );
      expect(placements, isEmpty);
    });

    test('vertical + scaleToFit false: alignment controls dx', () {
      final sizes = [(width: 50.0, height: 40.0), (width: 30.0, height: 20.0)];

      final start = computeMergePlacements(
        sizes: sizes,
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: false,
        alignment: MergeAlignment.start,
      );
      expect(start[1].dx, 0);

      final center = computeMergePlacements(
        sizes: sizes,
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: false,
        alignment: MergeAlignment.center,
      );
      expect(center[1].dx, (50 - 30) / 2);

      final end = computeMergePlacements(
        sizes: sizes,
        direction: MergeDirection.vertical,
        spacing: 0,
        scaleToFit: false,
        alignment: MergeAlignment.end,
      );
      expect(end[1].dx, 50 - 30);
    });

    test('vertical placements stack along dy with spacing', () {
      final placements = computeMergePlacements(
        sizes: const [(width: 100, height: 50), (width: 100, height: 50)],
        direction: MergeDirection.vertical,
        spacing: 10,
        scaleToFit: true,
        alignment: MergeAlignment.center,
      );
      expect(placements[0].dy, 0);
      expect(placements[1].dy, 60);
    });

    test('horizontal placements stack along dx with spacing', () {
      final placements = computeMergePlacements(
        sizes: const [(width: 50, height: 100), (width: 50, height: 100)],
        direction: MergeDirection.horizontal,
        spacing: 10,
        scaleToFit: true,
        alignment: MergeAlignment.center,
      );
      expect(placements[0].dx, 0);
      expect(placements[1].dx, 60);
    });
  });
}
