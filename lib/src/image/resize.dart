/// How [PixelExactSize] fits the image into the requested box.
enum PixelImageFit() {
  /// Scale each axis independently to fill the box exactly (aspect ratio is
  /// not kept).
  stretch,

  /// Keep the aspect ratio and fit the whole image inside the box, padding
  /// the rest with [PixelExactSize.padColor].
  contain,

  /// Keep the aspect ratio and fill the whole box, cropping the overflow
  /// (centred).
  cover,
}

/// Produce an image of exactly [width] × [height] pixels.
///
/// Applied as the last step, after rotation. When set, `minWidth`,
/// `minHeight`, `maxWidth` and `maxHeight` are ignored.
class const PixelExactSize(
  this.width,
  this.height, {
  this.fit = .contain,
  this.padColor = 0xFF000000,
}) {
  this : assert(width > 0 && height > 0);

  final int width;
  final int height;
  final PixelImageFit fit;

  /// ARGB colour for the padding used by [PixelImageFit.contain]
  /// (for example `0xFFFFFFFF` for white).
  final int padColor;
}

/// Extra resize options appended to the native argument lists. Indices of
/// the base arguments are unchanged; 0 means "not set".
List<int> resizeWireArgs({
  int? maxWidth,
  int? maxHeight,
  PixelExactSize? exactSize,
}) {
  assert(maxWidth == null || maxWidth > 0, 'maxWidth must be > 0');
  assert(maxHeight == null || maxHeight > 0, 'maxHeight must be > 0');
  return [
    maxWidth ?? 0,
    maxHeight ?? 0,
    exactSize?.width ?? 0,
    exactSize?.height ?? 0,
    exactSize?.fit.index ?? 0,
    exactSize?.padColor ?? 0,
  ];
}
