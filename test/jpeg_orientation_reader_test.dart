import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_compressor/src/core/jpeg_orientation_reader.dart';

Uint8List _jpeg({int? exifOrientation}) {
  final image = img.Image(width: 20, height: 10);
  img.fill(image, color: img.ColorRgb8(1, 2, 3));
  if (exifOrientation != null) {
    image.exif.imageIfd.orientation = exifOrientation;
  }
  return img.encodeJpg(image);
}

void main() {
  test('readRawJpegOrientation reads the tag when present', () {
    expect(readRawJpegOrientation(_jpeg(exifOrientation: 6)), 6);
    expect(readRawJpegOrientation(_jpeg(exifOrientation: 3)), 3);
  });

  test('readRawJpegOrientation returns null with no EXIF at all', () {
    expect(readRawJpegOrientation(_jpeg()), isNull);
  });

  test('readRawJpegOrientation returns null for non-JPEG bytes', () {
    expect(
      readRawJpegOrientation(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
      isNull,
    );
    expect(readRawJpegOrientation(Uint8List(0)), isNull);
  });

  test('hasJpegExif is true exactly when an APP1/EXIF segment is present', () {
    expect(hasJpegExif(_jpeg(exifOrientation: 1)), isTrue);
    expect(hasJpegExif(_jpeg()), isFalse);
  });

  test('hasJpegExif returns false for non-JPEG bytes', () {
    expect(hasJpegExif(Uint8List.fromList([0x00, 0x01, 0x02])), isFalse);
  });
}
