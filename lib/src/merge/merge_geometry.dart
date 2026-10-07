import 'dart:math' as math;

import 'merge_options.dart';

/// A source's displayed size. Kept free of `dart:ui` so the layout maths is
/// trivially unit-testable.
typedef MergeImageSize = ({double width, double height});

/// One image's rectangle in the merged canvas.
typedef MergePlacement = ({double dx, double dy, double width, double height});

typedef MergeLayoutResult = ({
  double width,
  double height,
  List<MergePlacement> placements,

  /// Clamp factor applied (≤ 1); scales spacing-like options such as
  /// corner radius.
  double scale,
});

typedef _RawLayout = ({
  double width,
  double height,
  List<MergePlacement> placements,
});

/// Hard limits that keep rendering within GPU texture sizes and memory.
const int kMergeMaxSide = 8192;
const int kMergeMaxPixels = 32 * 1000 * 1000;
const int kMergeDefaultLongSide = 4096;

/// Lays out [sizes] (all > 0) and scales the result down to the output
/// bounds. Placements are in final output pixels.
MergeLayoutResult computeMergeLayout({
  required List<MergeImageSize> sizes,
  required PixelMergeOptions options,
}) {
  assert(sizes.isNotEmpty);
  final inner = switch (options.layout) {
    .vertical => _linear(sizes, options, vertical: true),
    .horizontal => _linear(sizes, options, vertical: false),
    .grid => _grid(sizes, options),
  };
  final pad = options.padding;
  final _RawLayout raw = pad <= 0
      ? inner
      : (
          width: inner.width + 2 * pad,
          height: inner.height + 2 * pad,
          placements: [
            for (final p in inner.placements)
              (
                dx: p.dx + pad,
                dy: p.dy + pad,
                width: p.width,
                height: p.height,
              ),
          ],
        );
  final scale = mergeOutputScale(raw.width, raw.height, options);
  if (scale >= 1) {
    return (
      width: raw.width,
      height: raw.height,
      placements: raw.placements,
      scale: 1.0,
    );
  }
  return (
    scale: scale,
    width: raw.width * scale,
    height: raw.height * scale,
    placements: [
      for (final p in raw.placements)
        (
          dx: p.dx * scale,
          dy: p.dy * scale,
          width: p.width * scale,
          height: p.height * scale,
        ),
    ],
  );
}

/// Factor (≤ 1) that brings a [width]×[height] canvas within the configured
/// and hard output limits.
double mergeOutputScale(
  double width,
  double height,
  PixelMergeOptions options,
) {
  if (width <= 0 || height <= 0) return 1;
  var scale = 1.0;
  final maxW = options.maxOutputWidth;
  final maxH = options.maxOutputHeight;
  if (maxW == null && maxH == null) {
    scale = math.min(scale, kMergeDefaultLongSide / math.max(width, height));
  }
  if (maxW != null && maxW > 0) scale = math.min(scale, maxW / width);
  if (maxH != null && maxH > 0) scale = math.min(scale, maxH / height);
  scale = math.min(scale, kMergeMaxSide / math.max(width, height));
  scale = math.min(scale, math.sqrt(kMergeMaxPixels / (width * height)));
  return scale;
}

double _cross(PixelMergeAlignment a, double space, double size) => switch (a) {
  .start => 0,
  .center => (space - size) / 2,
  .end => space - size,
};

_RawLayout _linear(
  List<MergeImageSize> sizes,
  PixelMergeOptions o, {
  required bool vertical,
}) {
  // Cross-axis size: the widest (vertical) / tallest (horizontal) source.
  final cross = sizes
      .map((s) => vertical ? s.width : s.height)
      .reduce(math.max);
  final placements = <MergePlacement>[];
  var offset = 0.0;
  for (final s in sizes) {
    final double w, h;
    if (o.scaleToFit) {
      w = vertical ? cross : s.width * cross / s.height;
      h = vertical ? s.height * cross / s.width : cross;
    } else {
      w = s.width;
      h = s.height;
    }
    placements.add(
      vertical
          ? (dx: _cross(o.alignment, cross, w), dy: offset, width: w, height: h)
          : (
              dx: offset,
              dy: _cross(o.alignment, cross, h),
              width: w,
              height: h,
            ),
    );
    offset += (vertical ? h : w) + o.spacing;
  }
  final main = offset - o.spacing;
  return vertical
      ? (width: cross, height: main, placements: placements)
      : (width: main, height: cross, placements: placements);
}

_RawLayout _grid(List<MergeImageSize> sizes, PixelMergeOptions o) {
  final columns = math.max(1, o.gridColumns);
  final rows = <List<int>>[
    for (var i = 0; i < sizes.length; i += columns)
      [for (var j = i; j < math.min(i + columns, sizes.length); j++) j],
  ];

  // Each row at a common height, then (scaleToFit) full rows justified to
  // the widest row; a short last row keeps that row height and is aligned.
  final refHeight = sizes.map((s) => s.height).reduce(math.max);
  final rowItems = <List<({double w, double h})>>[];
  for (final row in rows) {
    rowItems.add([
      for (final i in row)
        o.scaleToFit
            ? (w: sizes[i].width * refHeight / sizes[i].height, h: refHeight)
            : (w: sizes[i].width, h: sizes[i].height),
    ]);
  }
  double rowWidth(List<({double w, double h})> items) =>
      items.fold(0.0, (sum, it) => sum + it.w) + o.spacing * (items.length - 1);
  final fullRows = [
    for (var r = 0; r < rows.length; r++)
      if (rows[r].length == columns || rows.length == 1) r,
  ];
  final canvasWidth =
      (fullRows.isEmpty ? rowItems : [for (final r in fullRows) rowItems[r]])
          .map(rowWidth)
          .reduce(math.max);

  final placements = List<MergePlacement?>.filled(sizes.length, null);
  var y = 0.0;
  for (var r = 0; r < rows.length; r++) {
    var items = rowItems[r];
    final natural = rowWidth(items);
    final isFull = rows[r].length == columns || rows.length == 1;
    if (o.scaleToFit && (isFull || natural > canvasWidth)) {
      // Justify: scale the row so it spans the canvas exactly.
      final gaps = o.spacing * (items.length - 1);
      final k = (canvasWidth - gaps) / (natural - gaps);
      items = [for (final it in items) (w: it.w * k, h: it.h * k)];
    }
    final rowHeight = items.map((it) => it.h).reduce(math.max);
    var x = _cross(o.alignment, canvasWidth, rowWidth(items));
    if (x < 0) x = 0;
    for (var c = 0; c < items.length; c++) {
      placements[rows[r][c]] = (
        dx: x,
        dy: y + _cross(o.alignment, rowHeight, items[c].h),
        width: items[c].w,
        height: items[c].h,
      );
      x += items[c].w + o.spacing;
    }
    y += rowHeight + o.spacing;
  }
  final canvasW = math.max(
    canvasWidth,
    placements.map((p) => p!.dx + p.width).reduce(math.max),
  );
  return (
    width: canvasW,
    height: y - o.spacing,
    placements: placements.cast<MergePlacement>(),
  );
}
