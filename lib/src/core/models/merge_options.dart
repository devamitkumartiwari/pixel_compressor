import 'dart:ui' as ui;

import '../enums/merge_alignment.dart';
import '../enums/merge_direction.dart';

/// Settings for [PixelCompressor.merge] — combining 2+ images into one.
class MergeOptions {
  const MergeOptions({
    this.direction = MergeDirection.vertical,
    this.spacing = 0,
    this.background = const ui.Color(0x00000000),
    this.scaleToFit = true,
    this.alignment = MergeAlignment.center,
    this.outputPath,
  }) : assert(spacing >= 0, 'spacing must be zero or positive');

  final MergeDirection direction;

  /// Gap between adjacent images along the main axis. In output pixels
  /// for [ImageMerger.combine]; in logical pixels for [MergeView] (scaled
  /// by the capture `pixelRatio`, same as the rest of the widget).
  final double spacing;

  /// Fills space not covered by an image (visible when [scaleToFit] is
  /// `false`) or shows through transparent sources. Default: transparent.
  final ui.Color background;

  /// `true` (default): every image is scaled, preserving its own aspect
  /// ratio, so its cross-axis size matches the widest/tallest source.
  /// `false`: images keep their native pixel size; [alignment] places
  /// them within the shared cross-axis size.
  final bool scaleToFit;

  /// Only applied when [scaleToFit] is `false`.
  final MergeAlignment alignment;

  /// `null` writes to a temp file under [Directory.systemTemp]. Unlike
  /// `ImageCompressOptions.outputPath`, this does **not** route through
  /// `PixelCompressor.cache` — merging is pure Dart and has no native
  /// cache manager to register with. Pass an explicit path if you need
  /// the output tracked/cleaned up by your own app.
  final String? outputPath;

  @override
  String toString() =>
      'MergeOptions(direction: $direction, spacing: $spacing, '
      'scaleToFit: $scaleToFit, alignment: $alignment)';
}
