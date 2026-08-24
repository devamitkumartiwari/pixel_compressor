import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/exceptions/pixel_compressor_exception.dart';

/// Captures a PNG snapshot of the `MergeView` this controller is attached
/// to. Create one, pass it to `MergeView.controller`, then call
/// [capturePng] after the widget has rendered at least one frame (e.g.
/// from a button's `onPressed`, not `initState`).
class MergeCaptureController {
  /// Attached to the `MergeView`'s [RepaintBoundary] — not meant to be
  /// read or assigned directly; used internally by [capturePng].
  final GlobalKey boundaryKey = GlobalKey();

  /// [pixelRatio] scales output resolution independently of the on-screen
  /// logical size (e.g. `2.0` for a sharper capture). Default `1.0`.
  ///
  /// Throws [InvalidMediaException] if no `MergeView` is currently
  /// attached, or the attached render object isn't a
  /// [RenderRepaintBoundary]. Throws [EncodingException] if rasterizing
  /// or PNG encoding fails.
  Future<Uint8List> capturePng({double pixelRatio = 1.0}) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      throw const InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'No MergeView is currently attached to this controller — '
            'capturePng() must be called after the widget has rendered '
            'at least one frame.',
      );
    }
    if (renderObject is! RenderRepaintBoundary) {
      throw const InvalidMediaException(
        nativeCode: 'invalid_media',
        nativeMessage:
            'The attached render object is not a RenderRepaintBoundary.',
      );
    }

    final ui.Image image;
    try {
      image = await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (e) {
      throw EncodingException(
        nativeCode: 'encoding_error',
        nativeMessage: 'Failed to rasterize the merged widget: $e',
      );
    }

    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const EncodingException(
          nativeCode: 'encoding_error',
          nativeMessage: 'Failed to encode the captured widget to PNG.',
        );
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
