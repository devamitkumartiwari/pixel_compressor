import 'enums/merge_alignment.dart';
import 'enums/merge_direction.dart';

/// The intrinsic pixel size of one source image, decoupled from `ui.Image`
/// purely so this file has no `dart:ui` dependency and stays trivially
/// unit-testable.
typedef MergeImageSize = ({double width, double height});

/// One image's computed position/size within the merged canvas.
typedef MergePlacement = ({double dx, double dy, double width, double height});

/// The merged canvas's overall pixel size for [sizes] under [direction],
/// [spacing] and [scaleToFit]. [sizes] must be non-empty.
({double width, double height}) computeMergeCanvasSize({
  required List<MergeImageSize> sizes,
  required MergeDirection direction,
  required double spacing,
  required bool scaleToFit,
}) {
  assert(sizes.isNotEmpty, 'computeMergeCanvasSize requires at least one size');
  final gaps = spacing * (sizes.length - 1);
  switch (direction) {
    case MergeDirection.vertical:
      final crossAxis = sizes.fold<double>(
        0,
        (m, s) => s.width > m ? s.width : m,
      );
      final main = sizes.fold<double>(
        0,
        (sum, s) =>
            sum + (scaleToFit ? s.height * crossAxis / s.width : s.height),
      );
      return (width: crossAxis, height: main + gaps);
    case MergeDirection.horizontal:
      final crossAxis = sizes.fold<double>(
        0,
        (m, s) => s.height > m ? s.height : m,
      );
      final main = sizes.fold<double>(
        0,
        (sum, s) =>
            sum + (scaleToFit ? s.width * crossAxis / s.height : s.width),
      );
      return (width: main + gaps, height: crossAxis);
  }
}

/// Per-image placement (top-left offset + draw size) within the canvas
/// [computeMergeCanvasSize] would produce for the same arguments.
List<MergePlacement> computeMergePlacements({
  required List<MergeImageSize> sizes,
  required MergeDirection direction,
  required double spacing,
  required bool scaleToFit,
  required MergeAlignment alignment,
}) {
  if (sizes.isEmpty) return const [];
  final canvas = computeMergeCanvasSize(
    sizes: sizes,
    direction: direction,
    spacing: spacing,
    scaleToFit: scaleToFit,
  );
  final placements = <MergePlacement>[];
  var offset = 0.0;
  for (final size in sizes) {
    final double w, h, dx, dy;
    switch (direction) {
      case MergeDirection.vertical:
        w = scaleToFit ? canvas.width : size.width;
        h = scaleToFit ? size.height * canvas.width / size.width : size.height;
        dx = _crossOffset(alignment, canvas.width, w);
        dy = offset;
        offset += h + spacing;
      case MergeDirection.horizontal:
        h = scaleToFit ? canvas.height : size.height;
        w = scaleToFit ? size.width * canvas.height / size.height : size.width;
        dy = _crossOffset(alignment, canvas.height, h);
        dx = offset;
        offset += w + spacing;
    }
    placements.add((dx: dx, dy: dy, width: w, height: h));
  }
  return placements;
}

double _crossOffset(
  MergeAlignment alignment,
  double crossSize,
  double itemSize,
) => switch (alignment) {
  MergeAlignment.start => 0,
  MergeAlignment.center => (crossSize - itemSize) / 2,
  MergeAlignment.end => crossSize - itemSize,
};
