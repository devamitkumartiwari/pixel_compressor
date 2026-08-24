/// Cross-axis placement of an image within the merged canvas — only
/// visible when [MergeOptions.scaleToFit] is `false` and a source is
/// narrower/shorter than the canvas's shared cross-axis size.
enum MergeAlignment {
  /// Flush with the canvas's leading edge (left for vertical, top for
  /// horizontal).
  start,

  /// Centered within the canvas's cross-axis size.
  center,

  /// Flush with the canvas's trailing edge (right for vertical, bottom
  /// for horizontal).
  end,
}
