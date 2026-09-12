import 'dart:typed_data';

import 'enums/image_format.dart';

/// Detects [bytes]' image format from its magic-number header, for
/// deciding whether a compress request routes to the pure-Dart JPEG/PNG
/// engine or the native WebP/HEIC engines when `options.format` is `null`
/// (meaning "keep the source's own format"). Defaults to [ImageFormat.jpeg]
/// for anything unrecognized, matching the native engines' own
/// extension-based fallback (`ImageFormatCodec.detectFromPath`).
ImageFormat sniffImageFormat(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
    return ImageFormat.jpeg;
  }
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47])) {
    return ImageFormat.png;
  }
  if (bytes.length >= 12 &&
      _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) && // 'RIFF'
      _matchesAt(bytes, 8, const [0x57, 0x45, 0x42, 0x50])) {
    // 'WEBP'
    return ImageFormat.webp;
  }
  if (_isHeic(bytes)) {
    return ImageFormat.heic;
  }
  return ImageFormat.jpeg;
}

bool _isHeic(Uint8List bytes) {
  // ISOBMFF: a 4-byte box size, then 'ftyp', then a 4-byte major brand.
  if (bytes.length < 12) return false;
  if (!_matchesAt(bytes, 4, const [0x66, 0x74, 0x79, 0x70])) {
    // 'ftyp'
    return false;
  }
  final brand = String.fromCharCodes(bytes.sublist(8, 12));
  const heicBrands = {
    'heic',
    'heix',
    'heim',
    'heis',
    'hevc',
    'hevx',
    'mif1',
    'msf1',
  };
  return heicBrands.contains(brand);
}

bool _startsWith(Uint8List bytes, List<int> prefix) =>
    _matchesAt(bytes, 0, prefix);

bool _matchesAt(Uint8List bytes, int offset, List<int> pattern) {
  if (bytes.length < offset + pattern.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (bytes[offset + i] != pattern[i]) return false;
  }
  return true;
}
