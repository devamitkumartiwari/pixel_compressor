import 'dart:typed_data';

/// Reads the raw EXIF orientation tag (1-8) directly from JPEG [bytes],
/// independent of `package:image`'s own decode step.
///
/// This exists because `package:image`'s JPEG decoder (`getImageFromJpeg`)
/// *unconditionally* bakes the EXIF orientation into the decoded pixels
/// during `decodeImage`/`decodeJpg`, with no way to opt out, and clears
/// the orientation tag on the returned `Image` to null in the process —
/// so by the time a caller can inspect `Image.exif.imageIfd.orientation`,
/// the original value is already gone. To support `autoCorrectOrientation:
/// false` (undoing that forced bake) at all, the original tag has to be
/// read independently, before decode, the same way the native engines
/// read it via `ExifInterface`/`ImageIO`.
///
/// Returns `null` if [bytes] isn't a JPEG, has no APP1/EXIF segment, or no
/// orientation tag.
int? readRawJpegOrientation(Uint8List bytes) {
  final exif = _findJpegExifSegment(bytes);
  if (exif == null) return null;
  return _readOrientationFromTiff(bytes, exif.tiffStart);
}

/// Whether [bytes] is a JPEG carrying an APP1/EXIF segment at all,
/// independent of whether that segment has an orientation tag — used for
/// `MediaInfo.exifPresent`. Shares the same marker walk as
/// [readRawJpegOrientation].
bool hasJpegExif(Uint8List bytes) => _findJpegExifSegment(bytes) != null;

class _ExifSegment {
  const _ExifSegment(this.tiffStart);
  final int tiffStart;
}

_ExifSegment? _findJpegExifSegment(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null; // malformed marker stream
    final marker = bytes[offset + 1];

    // Markers with no payload/length field.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      offset += 2;
      if (marker == 0xD9) return null; // EOI
      continue;
    }
    if (marker == 0xDA) return null; // SOS — compressed scan data follows, stop

    if (offset + 4 > bytes.length) return null;
    final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2) return null;

    if (marker == 0xE1) {
      final tiffStart = _tryReadExifHeader(
        bytes,
        offset + 4,
        segmentLength - 2,
      );
      if (tiffStart != null) return _ExifSegment(tiffStart);
    }

    offset += 2 + segmentLength;
  }
  return null;
}

/// Validates the "Exif\0\0" signature at [payloadStart] and returns the
/// TIFF structure's start offset, or `null` if this APP1 segment isn't an
/// EXIF one (e.g. an XMP APP1 segment, which uses a different signature).
int? _tryReadExifHeader(Uint8List bytes, int payloadStart, int payloadLength) {
  if (payloadLength < 6 || payloadStart + 6 > bytes.length) return null;
  const exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  for (var i = 0; i < 6; i++) {
    if (bytes[payloadStart + i] != exifHeader[i]) return null;
  }
  return payloadStart + 6;
}

int? _readOrientationFromTiff(Uint8List bytes, int tiffStart) {
  if (tiffStart + 8 > bytes.length) return null;
  final bigEndian =
      bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D; // 'MM' vs 'II'

  int readU16(int o) => bigEndian
      ? (bytes[o] << 8) | bytes[o + 1]
      : (bytes[o + 1] << 8) | bytes[o];
  int readU32(int o) => bigEndian
      ? (bytes[o] << 24) |
            (bytes[o + 1] << 16) |
            (bytes[o + 2] << 8) |
            bytes[o + 3]
      : (bytes[o + 3] << 24) |
            (bytes[o + 2] << 16) |
            (bytes[o + 1] << 8) |
            bytes[o];

  final ifd0Offset = readU32(tiffStart + 4);
  final ifd0Start = tiffStart + ifd0Offset;
  if (ifd0Start < 0 || ifd0Start + 2 > bytes.length) return null;

  final entryCount = readU16(ifd0Start);
  for (var i = 0; i < entryCount; i++) {
    final entryOffset = ifd0Start + 2 + i * 12;
    if (entryOffset + 12 > bytes.length) break;
    final tag = readU16(entryOffset);
    if (tag == 0x0112) {
      // Orientation is always type SHORT (2 bytes), stored in the first 2
      // bytes of the 4-byte value field regardless of byte order position.
      final valueFieldOffset = entryOffset + 8;
      return readU16(valueFieldOffset);
    }
  }
  return null;
}
