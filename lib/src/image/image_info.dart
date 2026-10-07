import 'dart:typed_data';

import 'compress_format.dart';

/// Size and format of an encoded image, read from its header without
/// decoding pixels. Pure Dart, so it works on every platform including web.
class const PixelImageInfo({
  required this.width,
  required this.height,
  required this.format,
  this.orientation = 1,
}) {
  /// Width as displayed, i.e. after the EXIF/HEIF rotation is applied.
  final int width;

  /// Height as displayed, i.e. after the EXIF/HEIF rotation is applied.
  final int height;

  /// Container format, or null for formats pixel_compressor doesn't write
  /// (GIF, BMP, AVIF, ...), which are still measured when possible.
  final PixelImageFormat? format;

  /// EXIF orientation (1–8; 1 = upright). HEIF `irot` is mapped to 1/6/3/8.
  final int orientation;

  /// Reads [bytes]' header. Returns null if the format isn't recognised or
  /// the header is truncated/corrupt (never throws).
  static PixelImageInfo? fromBytes(Uint8List bytes) {
    try {
      return _parse(bytes);
    } on RangeError {
      return null;
    }
  }

  @override
  String toString() =>
      'PixelImageInfo(${width}x$height, ${format?.name ?? 'unknown'}, orientation $orientation)';
}

/// A compressed image together with its [PixelImageInfo].
class const PixelImageResult(this.bytes, this.info) {
  final Uint8List bytes;
  final PixelImageInfo info;
}

PixelImageInfo? _parse(Uint8List b) {
  if (b.length < 12) return null;
  // PNG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final d = ByteData.sublistView(b);
    return PixelImageInfo(
      width: d.getUint32(16),
      height: d.getUint32(20),
      format: .png,
    );
  }
  // JPEG
  if (b[0] == 0xFF && b[1] == 0xD8) return _jpeg(b);
  // WebP
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) return _webp(b);
  // ISO BMFF (HEIC / HEIF / AVIF)
  if (_ascii(b, 4, 'ftyp')) return _heif(b);
  // GIF
  if (_ascii(b, 0, 'GIF8')) {
    final d = ByteData.sublistView(b);
    return PixelImageInfo(
      width: d.getUint16(6, Endian.little),
      height: d.getUint16(8, Endian.little),
      format: null,
    );
  }
  // BMP
  if (b[0] == 0x42 && b[1] == 0x4D && b.length >= 26) {
    final d = ByteData.sublistView(b);
    return PixelImageInfo(
      width: d.getInt32(18, Endian.little).abs(),
      height: d.getInt32(22, Endian.little).abs(),
      format: null,
    );
  }
  return null;
}

bool _ascii(Uint8List b, int offset, String s) {
  if (offset + s.length > b.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[offset + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

PixelImageInfo _oriented(int w, int h, PixelImageFormat? f, int orientation) {
  // Orientations 5–8 swap the axes.
  final swap = orientation >= 5 && orientation <= 8;
  return PixelImageInfo(
    width: swap ? h : w,
    height: swap ? w : h,
    format: f,
    orientation: orientation,
  );
}

PixelImageInfo? _jpeg(Uint8List b) {
  final d = ByteData.sublistView(b);
  var orientation = 1;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    var marker = b[i + 1];
    // Fill bytes.
    while (marker == 0xFF && i + 2 < b.length) {
      i++;
      marker = b[i + 1];
    }
    // Standalone markers have no length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null; // EOI / SOS before SOF
    final length = d.getUint16(i + 2);
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final h = d.getUint16(i + 5);
      final w = d.getUint16(i + 7);
      return _oriented(w, h, .jpeg, orientation);
    }
    if (marker == 0xE1 && _ascii(b, i + 4, 'Exif')) {
      orientation = _exifOrientation(b, i + 10, length - 8) ?? orientation;
    }
    i += 2 + length;
  }
  return null;
}

/// Orientation tag (0x0112) from a TIFF block at [start].
int? _exifOrientation(Uint8List b, int start, int length) {
  if (length < 8 || start + 8 > b.length) return null;
  final d = ByteData.sublistView(b);
  final endian = _ascii(b, start, 'II') ? Endian.little : Endian.big;
  final ifd = start + d.getUint32(start + 4, endian);
  if (ifd + 2 > b.length) return null;
  final count = d.getUint16(ifd, endian);
  for (var e = 0; e < count; e++) {
    final entry = ifd + 2 + e * 12;
    if (entry + 12 > b.length) return null;
    if (d.getUint16(entry, endian) == 0x0112) {
      final value = d.getUint16(entry + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

PixelImageInfo? _webp(Uint8List b) {
  final d = ByteData.sublistView(b);
  if (_ascii(b, 12, 'VP8 ') && b.length >= 30) {
    return PixelImageInfo(
      width: d.getUint16(26, Endian.little) & 0x3FFF,
      height: d.getUint16(28, Endian.little) & 0x3FFF,
      format: .webp,
    );
  }
  if (_ascii(b, 12, 'VP8L') && b.length >= 25) {
    final b0 = b[21], b1 = b[22], b2 = b[23], b3 = b[24];
    return PixelImageInfo(
      width: 1 + (((b1 & 0x3F) << 8) | b0),
      height: 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6)),
      format: .webp,
    );
  }
  if (_ascii(b, 12, 'VP8X') && b.length >= 30) {
    int u24(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
    return PixelImageInfo(
      width: 1 + u24(24),
      height: 1 + u24(27),
      format: .webp,
    );
  }
  return null;
}

PixelImageInfo? _heif(Uint8List b) {
  final d = ByteData.sublistView(b);
  final brand = String.fromCharCodes(b.sublist(8, 12));
  final format = switch (brand) {
    'heic' ||
    'heix' ||
    'hevc' ||
    'heim' ||
    'heis' ||
    'mif1' ||
    'msf1' => PixelImageFormat.heic,
    _ => null,
  };
  var bestW = 0, bestH = 0, rotation = 0;

  // Walks boxes in [start, end); descends into the containers on the path
  // meta → iprp → ipco.
  void walk(int start, int end) {
    var p = start;
    while (p + 8 <= end) {
      var size = d.getUint32(p);
      final type = String.fromCharCodes(b.sublist(p + 4, p + 8));
      var header = 8;
      if (size == 1) {
        if (p + 16 > end) return;
        // Two 32-bit reads: ByteData.getUint64 is unsupported on the web.
        size = d.getUint32(p + 8) * 0x100000000 + d.getUint32(p + 12);
        header = 16;
      } else if (size == 0) {
        size = end - p;
      }
      if (size < header || p + size > end) return;
      final body = p + header;
      switch (type) {
        case 'meta':
          walk(body + 4, p + size); // full box: version + flags
        case 'iprp' || 'ipco':
          walk(body, p + size);
        case 'ispe':
          if (body + 12 <= p + size) {
            final w = d.getUint32(body + 4);
            final h = d.getUint32(body + 8);
            if (w * h > bestW * bestH) {
              bestW = w;
              bestH = h;
            }
          }
        case 'irot':
          if (body < p + size) rotation = b[body] & 0x03;
      }
      p += size;
    }
  }

  walk(0, b.length);
  if (bestW == 0 || bestH == 0) return null;
  // irot is counter-clockwise quarter turns; map to the EXIF equivalent.
  const toExif = [1, 8, 3, 6];
  return _oriented(bestW, bestH, format, toExif[rotation]);
}
