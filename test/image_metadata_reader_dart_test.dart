import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/image_metadata_reader_dart.dart';

Uint8List _jpeg(int width, int height, {int? exifOrientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  if (exifOrientation != null) {
    image.exif.imageIfd.orientation = exifOrientation;
  }
  return img.encodeJpg(image);
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(40, 50, 60));
  return img.encodePng(image);
}

void main() {
  test('reads JPEG dimensions and mediaType without EXIF', () {
    final info = tryReadImageMetadataDart(_jpeg(320, 200), sizeBytes: 12345);
    expect(info, isNotNull);
    expect(info!.mediaType, MediaType.image);
    expect(info.width, 320);
    expect(info.height, 200);
    expect(info.format, 'jpeg');
    expect(info.sizeBytes, 12345);
    expect(info.exifPresent, isFalse);
    expect(info.orientation, isNull);
  });

  test('reads JPEG EXIF presence and orientation', () {
    final info = tryReadImageMetadataDart(
      _jpeg(100, 50, exifOrientation: 6),
      sizeBytes: 999,
    );
    expect(info, isNotNull);
    expect(info!.exifPresent, isTrue);
    expect(info.orientation, 6);
    // Dimensions are the raw (pre-any-correction) SOF values — this
    // reader never rotates, just reports what's on disk.
    expect(info.width, 100);
    expect(info.height, 50);
  });

  test('reads PNG dimensions with exifPresent always false', () {
    final info = tryReadImageMetadataDart(_png(64, 48), sizeBytes: 500);
    expect(info, isNotNull);
    expect(info!.mediaType, MediaType.image);
    expect(info.width, 64);
    expect(info.height, 48);
    expect(info.format, 'png');
    expect(info.exifPresent, isFalse);
  });

  test('returns null (fall back to native) for non-image bytes', () {
    final info = tryReadImageMetadataDart(
      Uint8List.fromList([
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
      ]), // mp4 'ftyp'
      sizeBytes: 1,
    );
    expect(info, isNull);
  });

  test('returns null for a truncated JPEG missing its SOF marker', () {
    final jpeg = _jpeg(100, 100);
    // Cut it off right after SOI, before any real markers.
    final truncated = jpeg.sublist(0, 4);
    expect(tryReadImageMetadataDart(truncated, sizeBytes: 4), isNull);
  });

  test('returns null for a truncated PNG missing its IHDR', () {
    final png = _png(100, 100);
    final truncated = png.sublist(0, 10);
    expect(tryReadImageMetadataDart(truncated, sizeBytes: 10), isNull);
  });

  test('returns null for empty bytes', () {
    expect(tryReadImageMetadataDart(Uint8List(0), sizeBytes: 0), isNull);
  });
}
