import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/image_format_sniffer.dart';

Uint8List _bytes(List<int> header, {int totalLength = 20}) {
  final bytes = Uint8List(totalLength);
  bytes.setRange(0, header.length, header);
  return bytes;
}

void main() {
  test('detects JPEG from its magic header', () {
    expect(
      sniffImageFormat(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
      ImageFormat.jpeg,
    );
  });

  test('detects PNG from its magic header', () {
    expect(
      sniffImageFormat(
        _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      ImageFormat.png,
    );
  });

  test('detects WebP from its RIFF/WEBP header', () {
    final bytes = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, // 'RIFF'
      0x00, 0x00, 0x00, 0x00, // chunk size (unused by the sniffer)
      0x57, 0x45, 0x42, 0x50, // 'WEBP'
    ]);
    expect(sniffImageFormat(bytes), ImageFormat.webp);
  });

  test('detects HEIC from its ftyp box', () {
    final bytes = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, // box size (unused by the sniffer)
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x68, 0x65, 0x69, 0x63, // 'heic' brand
    ]);
    expect(sniffImageFormat(bytes), ImageFormat.heic);
  });

  test('defaults to JPEG for unrecognized bytes, matching native fallback', () {
    expect(
      sniffImageFormat(_bytes([0x00, 0x11, 0x22, 0x33])),
      ImageFormat.jpeg,
    );
    expect(sniffImageFormat(Uint8List(0)), ImageFormat.jpeg);
  });

  test('does not crash on very short input', () {
    expect(sniffImageFormat(Uint8List.fromList([0xFF])), ImageFormat.jpeg);
  });
}
