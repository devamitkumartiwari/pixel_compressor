import 'dart:typed_data';
import 'dart:ui' show Color;

import '../image/compress_format.dart';

/// How [PixelImageMerger] arranges the images.
enum PixelMergeLayout() {
  /// One column, top to bottom.
  vertical,

  /// One row, left to right.
  horizontal,

  /// Rows of [PixelMergeOptions.gridColumns] images, left to right then top
  /// to bottom. With `scaleToFit`, each full row is scaled to the same width
  /// (a justified gallery).
  grid,
}

/// Cross-axis placement when images don't fill the cross axis (only with
/// `scaleToFit: false`, or a short last grid row).
enum PixelMergeAlignment() {
  start,
  center,
  end,
}

/// Where a merge input comes from.
sealed class const PixelMergeSource() {
  /// A file on disk (not available on the web).
  const factory PixelMergeSource.file(String path) = PixelMergeFileSource;

  /// Encoded image bytes (JPEG, PNG, WebP, HEIC, GIF, BMP).
  const factory PixelMergeSource.bytes(Uint8List bytes) = PixelMergeBytesSource;

  /// A Flutter asset, e.g. `assets/photo.jpg`.
  const factory PixelMergeSource.asset(String name) = PixelMergeAssetSource;
}

class const PixelMergeFileSource(this.path) extends PixelMergeSource {
  final String path;

  @override
  String toString() => 'file($path)';
}

class const PixelMergeBytesSource(this.bytes) extends PixelMergeSource {
  final Uint8List bytes;

  @override
  String toString() => 'bytes(${bytes.length} B)';
}

class const PixelMergeAssetSource(this.name) extends PixelMergeSource {
  final String name;

  @override
  String toString() => 'asset($name)';
}

/// Settings for [PixelImageMerger.merge] and `PixelMergeView`.
class const PixelMergeOptions({
  this.layout = .vertical,
  this.gridColumns = 2,
  this.spacing = 0,
  this.padding = 0,
  this.cornerRadius = 0,
  this.alignment = .center,
  this.scaleToFit = true,
  this.background = const Color(0xFFFFFFFF),
  this.maxOutputWidth,
  this.maxOutputHeight,
  this.format = .png,
  this.quality = 90,
  this.outputPath,
}) {
  this
    : assert(gridColumns >= 1, 'gridColumns must be >= 1'),
      assert(spacing >= 0, 'spacing must be >= 0'),
      assert(padding >= 0, 'padding must be >= 0'),
      assert(cornerRadius >= 0, 'cornerRadius must be >= 0'),
      assert(quality >= 1 && quality <= 100, 'quality must be 1–100');

  final PixelMergeLayout layout;

  /// Images per row for [PixelMergeLayout.grid].
  final int gridColumns;

  /// Gap between images, in output pixels before any size clamping.
  final double spacing;

  /// Margin around the whole collage, filled with [background], in output
  /// pixels before any size clamping.
  final double padding;

  /// Rounds each image's corners (output pixels before clamping).
  final double cornerRadius;

  final PixelMergeAlignment alignment;

  /// true: images are scaled (aspect kept) so they share the cross-axis size
  /// (same width in a column, same height in a row). false: native sizes.
  final bool scaleToFit;

  /// Fills gaps and shows through transparent sources. Always made opaque
  /// for JPEG and HEIC output, which have no alpha channel.
  final Color background;

  /// The output is scaled down (never up) to fit these bounds. When both are
  /// null, the long side is limited to 4096 px. Hard limits of 8192 px per
  /// side and 32 megapixels always apply, so large inputs never fail.
  final int? maxOutputWidth;
  final int? maxOutputHeight;

  /// Output encoding. PNG comes straight from the renderer; other formats go
  /// through `PixelImageCompressor` (WebP isn't available on macOS).
  final PixelImageFormat format;

  /// Lossy quality (1–100) for JPEG, WebP and HEIC.
  final int quality;

  /// Also write the result here (not on the web).
  final String? outputPath;

  PixelMergeOptions copyWith({
    PixelMergeLayout? layout,
    int? gridColumns,
    double? spacing,
    double? padding,
    double? cornerRadius,
    PixelMergeAlignment? alignment,
    bool? scaleToFit,
    Color? background,
    int? maxOutputWidth,
    int? maxOutputHeight,
    PixelImageFormat? format,
    int? quality,
    String? outputPath,
  }) => PixelMergeOptions(
    layout: layout ?? this.layout,
    gridColumns: gridColumns ?? this.gridColumns,
    spacing: spacing ?? this.spacing,
    padding: padding ?? this.padding,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    alignment: alignment ?? this.alignment,
    scaleToFit: scaleToFit ?? this.scaleToFit,
    background: background ?? this.background,
    maxOutputWidth: maxOutputWidth ?? this.maxOutputWidth,
    maxOutputHeight: maxOutputHeight ?? this.maxOutputHeight,
    format: format ?? this.format,
    quality: quality ?? this.quality,
    outputPath: outputPath ?? this.outputPath,
  );
}

/// The merged image.
class const PixelMergeResult({
  required this.bytes,
  required this.width,
  required this.height,
  required this.format,
  required this.sourceCount,
  required this.elapsed,
  this.path,
}) {
  final Uint8List bytes;
  final int width;
  final int height;
  final PixelImageFormat format;

  /// Set when `outputPath` was given.
  final String? path;
  final int sourceCount;
  final Duration elapsed;
}
