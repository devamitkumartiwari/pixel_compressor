import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../image/errors.dart';
import 'image_merger.dart';
import 'merge_options.dart';

/// Exports what a [PixelMergeView] shows. Attach it to the view, then call
/// [capture] (e.g. from a button). The export runs the same renderer as
/// the preview at full output size, so it matches the preview exactly.
class PixelMergeCaptureController() {
  List<PixelMergeSource>? _sources;
  PixelMergeOptions? _options;

  /// Whether a [PixelMergeView] is attached.
  bool get isAttached => _sources != null;

  /// Renders and encodes the attached view's merge at full resolution.
  ///
  /// [options] overrides the view's options for this export (for example a
  /// different `format` or `outputPath`). Throws [PixelCompressError]
  /// (`invalid_input` when no view is attached).
  Future<PixelMergeResult> capture({PixelMergeOptions? options}) {
    final sources = _sources;
    final viewOptions = _options;
    if (sources == null || viewOptions == null) {
      throw PixelCompressError(
        'No PixelMergeView is attached to this controller.',
        code: 'invalid_input',
      );
    }
    return PixelImageMerger.merge(sources, options: options ?? viewOptions);
  }

  void _attach(List<PixelMergeSource> sources, PixelMergeOptions options) {
    _sources = sources;
    _options = options;
  }

  void _detach() {
    _sources = null;
    _options = null;
  }
}

/// Live preview of a merge. Renders with the same layout and decoder as
/// [PixelImageMerger.merge], sized to the space it's given (aspect ratio
/// kept), and re-renders when [sources] or [options] change.
class const PixelMergeView({
  super.key,
  required this.sources,
  this.options = const PixelMergeOptions(),
  this.controller,
  this.placeholder,
  this.errorBuilder,
}) extends StatefulWidget {
  final List<PixelMergeSource> sources;
  final PixelMergeOptions options;
  final PixelMergeCaptureController? controller;

  /// Shown while rendering. Defaults to an empty box.
  final Widget? placeholder;

  /// Shown when rendering fails. Defaults to the error message.
  final Widget Function(BuildContext context, PixelCompressError error)?
  errorBuilder;

  @override
  State<PixelMergeView> createState() => _PixelMergeViewState();
}

class _PixelMergeViewState() extends State<PixelMergeView> {
  ui.Image? _image;
  PixelCompressError? _error;
  int _generation = 0;
  double _renderedFor = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(widget.sources, widget.options);
  }

  @override
  void didUpdateWidget(PixelMergeView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) old.controller?._detach();
    widget.controller?._attach(widget.sources, widget.options);
    if (!identical(old.sources, widget.sources) ||
        old.options != widget.options) {
      _renderedFor = 0; // force a re-render at the next layout
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller?._detach();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(double maxSidePx) async {
    final generation = ++_generation;
    _renderedFor = maxSidePx;
    // Preview resolution: enough for the screen, far below the export size.
    final previewOptions = widget.options.copyWith(
      maxOutputWidth: maxSidePx.round(),
      maxOutputHeight: maxSidePx.round(),
    );
    try {
      final image = await renderMerge(widget.sources, previewOptions);
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _error = null;
      });
    } on PixelCompressError catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final side = [
          constraints.maxWidth,
          constraints.maxHeight,
        ].where((v) => v.isFinite).fold<double>(1024, (a, b) => a < b ? a : b);
        final target = (side * dpr).clamp(64, 2048).toDouble();
        if (_renderedFor == 0 ||
            (target - _renderedFor).abs() > _renderedFor * 0.25) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                (_renderedFor == 0 ||
                    (target - _renderedFor).abs() > _renderedFor * 0.25)) {
              _render(target);
            }
          });
        }
        final error = _error;
        if (error != null) {
          return widget.errorBuilder?.call(context, error) ??
              Center(child: Text(error.message, textAlign: .center));
        }
        final image = _image;
        if (image == null) return widget.placeholder ?? const SizedBox.shrink();
        return AspectRatio(
          aspectRatio: image.width / image.height,
          child: RawImage(image: image, fit: .contain),
        );
      },
    );
  }
}
