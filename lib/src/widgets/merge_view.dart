import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/enums/merge_alignment.dart';
import '../core/enums/merge_direction.dart';
import '../core/merge_geometry.dart';
import '../core/models/merge_options.dart';
import 'merge_capture_controller.dart';

/// Live, on-screen preview of a `PixelCompressor.merge`-style layout,
/// built from a real [Column]/[Row] instead of `dart:ui` canvas drawing.
/// Has no Material dependency, so it embeds in Material or Cupertino
/// apps alike.
///
/// Already wraps itself in a [RepaintBoundary] keyed by [controller];
/// call `controller.capturePng()` to get PNG bytes shaped like
/// `PixelCompressor.merge.combine`'s output, rasterized from exactly
/// what's on screen instead of re-decoding the sources.
///
/// [images] must be already-decoded — see `PixelCompressor.merge.decode`.
/// This widget does not dispose them; that's the caller's responsibility.
class MergeView extends StatelessWidget {
  const MergeView({
    super.key,
    required this.images,
    required this.controller,
    this.direction = MergeDirection.vertical,
    this.spacing = 0,
    this.background = const Color(0x00000000),
    this.scaleToFit = true,
    this.alignment = MergeAlignment.center,
  }) : assert(images.length > 0, 'MergeView needs at least one image');

  /// Mirrors direction/spacing/background/scaleToFit/alignment from a
  /// [MergeOptions] so a preview stays in sync with a headless call.
  factory MergeView.fromOptions({
    Key? key,
    required List<ui.Image> images,
    required MergeCaptureController controller,
    required MergeOptions options,
  }) => MergeView(
    key: key,
    images: images,
    controller: controller,
    direction: options.direction,
    spacing: options.spacing,
    background: options.background,
    scaleToFit: options.scaleToFit,
    alignment: options.alignment,
  );

  final List<ui.Image> images;
  final MergeCaptureController controller;
  final MergeDirection direction;
  final double spacing;
  final Color background;
  final bool scaleToFit;
  final MergeAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final isVertical = direction == MergeDirection.vertical;
    final sizes = images
        .map(
          (img) => (width: img.width.toDouble(), height: img.height.toDouble()),
        )
        .toList();
    final canvasSize = computeMergeCanvasSize(
      sizes: sizes,
      direction: direction,
      spacing: spacing,
      scaleToFit: scaleToFit,
    );
    final placements = computeMergePlacements(
      sizes: sizes,
      direction: direction,
      spacing: spacing,
      scaleToFit: scaleToFit,
      alignment: alignment,
    );
    final crossAlign = switch (alignment) {
      MergeAlignment.start => CrossAxisAlignment.start,
      MergeAlignment.center => CrossAxisAlignment.center,
      MergeAlignment.end => CrossAxisAlignment.end,
    };

    final children = <Widget>[
      for (var i = 0; i < images.length; i++) ...[
        SizedBox(
          width: placements[i].width,
          height: placements[i].height,
          child: RawImage(image: images[i], fit: BoxFit.fill),
        ),
        if (i < images.length - 1)
          SizedBox(
            width: isVertical ? 0 : spacing,
            height: isVertical ? spacing : 0,
          ),
      ],
    ];

    final linear = isVertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAlign,
            children: children,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAlign,
            children: children,
          );

    return RepaintBoundary(
      key: controller.boundaryKey,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: ColoredBox(color: background, child: linear),
      ),
    );
  }
}
