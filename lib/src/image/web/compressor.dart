import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart';

import '../compress_format.dart';
import '../resize.dart';

import 'log.dart' as logger;
import 'util.dart';

Future<Uint8List> resizeWithList({
  required Uint8List buffer,
  required int minWidth,
  required int minHeight,
  PixelImageFormat format = .jpeg,
  int quality = 88,
  int? maxWidth,
  int? maxHeight,
  PixelExactSize? exactSize,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final bitmap = await buffer.toImageBitmap();

  final srcWidth = bitmap.width;
  final srcHeight = bitmap.height;

  final scaleW = srcWidth / minWidth;
  final scaleH = srcHeight / minHeight;
  // Take the smaller downscale factor so at least one output dimension
  // meets its min bound; clamp at 1 so we never upscale.
  var scale = math.max(1.0, math.min(scaleW, scaleH));
  // Then shrink further if needed so the output fits inside the max bounds.
  if (maxWidth != null && maxWidth > 0) {
    scale = math.max(scale, srcWidth / maxWidth);
  }
  if (maxHeight != null && maxHeight > 0) {
    scale = math.max(scale, srcHeight / maxHeight);
  }
  final width = (srcWidth / scale).toInt();
  final height = (srcHeight / scale).toInt();

  logger.jsLog('src size', '$srcWidth x $srcHeight');

  final canvas = HTMLCanvasElement();
  final ctx = canvas.getContext('2d') as CanvasRenderingContext2D?;
  if (exactSize == null) {
    logger.jsLog('target size', '$width x $height');
    canvas.width = width;
    canvas.height = height;
    ctx?.clearRect(0, 0, width, height);
    ctx?.drawImage(bitmap, 0, 0, width, height);
  } else {
    final w = exactSize.width;
    final h = exactSize.height;
    logger.jsLog('exact size', '$w x $h (${exactSize.fit.name})');
    canvas.width = w;
    canvas.height = h;
    final rect = exactFitRect(srcWidth, srcHeight, w, h, exactSize.fit);
    if (exactSize.fit == .contain) {
      ctx?.fillStyle = _cssColor(exactSize.padColor).toJS;
      ctx?.fillRect(0, 0, w, h);
    } else {
      ctx?.clearRect(0, 0, w, h);
    }
    ctx?.drawImage(bitmap, rect.$1, rect.$2, rect.$3, rect.$4);
  }

  final blob = canvas.toDataUrl(format.type, quality / 100);
  final str = blob.split(',')[1];

  bitmap.close();
  final result = base64Decode(str);
  logger.dartLog('compressed image buffer length: ${result.length}');
  logger.dartLog('compressed took ${stopwatch.elapsedMilliseconds}ms');

  return result;
}

extension CompressExt on PixelImageFormat {
  String get type {
    switch (this) {
      case .jpeg:
        return 'image/jpeg';
      case .png:
        return 'image/png';
      case .webp:
        return 'image/webp';
      case .heic:
        throw UnimplementedError('heic is not support web');
    }
  }
}

/// Destination rect (x, y, width, height) for drawing a [srcW]×[srcH] image
/// into a [w]×[h] canvas with [fit]. Shared rule with the native platforms.
(double, double, double, double) exactFitRect(
  int srcW,
  int srcH,
  int w,
  int h,
  PixelImageFit fit,
) {
  switch (fit) {
    case .stretch:
      return (0, 0, w.toDouble(), h.toDouble());
    case .contain:
    case .cover:
      final sx = w / srcW;
      final sy = h / srcH;
      final s = fit == .contain ? math.min(sx, sy) : math.max(sx, sy);
      final dw = srcW * s;
      final dh = srcH * s;
      return ((w - dw) / 2, (h - dh) / 2, dw, dh);
  }
}

String _cssColor(int argb) {
  final a = ((argb >> 24) & 0xFF) / 255;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r, $g, $b, $a)';
}
