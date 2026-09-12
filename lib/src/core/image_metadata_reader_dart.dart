import 'dart:typed_data';

import 'enums/image_format.dart';
import 'enums/media_type.dart';
import 'image_format_sniffer.dart';
import 'jpeg_orientation_reader.dart';
import 'models/media_info.dart';

/// Reads [MediaInfo] for a JPEG/PNG source directly from its header bytes
/// — no decode, no native call. Returns `null` for anything that isn't
/// confidently a well-formed JPEG or PNG (including a source too large or
/// unusual to have its dimensions found within [prefixBytes]), so the
/// caller can fall back to the existing native `MetadataHostApi` path with
/// zero regression risk. Mirrors the compression engine's format split
/// (`image_format_sniffer.dart`) — WebP/HEIC/video are never handled here.
MediaInfo? tryReadImageMetadataDart(
  Uint8List prefixBytes, {
  required int sizeBytes,
}) {
  final sniffed = sniffImageFormat(prefixBytes);
  switch (sniffed) {
    case ImageFormat.jpeg:
      return _readJpegInfo(prefixBytes, sizeBytes: sizeBytes);
    case ImageFormat.png:
      return _readPngInfo(prefixBytes, sizeBytes: sizeBytes);
    case ImageFormat.webp:
    case ImageFormat.heic:
      return null;
  }
}

MediaInfo? _readJpegInfo(Uint8List bytes, {required int sizeBytes}) {
  final dims = _readJpegDimensions(bytes);
  if (dims == null) return null;
  return MediaInfo(
    mediaType: MediaType.image,
    sizeBytes: sizeBytes,
    width: dims.$1,
    height: dims.$2,
    format: 'jpeg',
    exifPresent: hasJpegExif(bytes),
    orientation: readRawJpegOrientation(bytes),
  );
}

MediaInfo? _readPngInfo(Uint8List bytes, {required int sizeBytes}) {
  final dims = _readPngDimensions(bytes);
  if (dims == null) return null;
  return MediaInfo(
    mediaType: MediaType.image,
    sizeBytes: sizeBytes,
    width: dims.$1,
    height: dims.$2,
    format: 'png',
    // package:image's PNG encoder has no EXIF-write support at all (see
    // image_engine_dart.dart), and PNG+EXIF is rare in practice — this is
    // a documented, accepted gap rather than a full PNG eXIf-chunk parser.
    exifPresent: false,
  );
}

/// Walks JPEG markers to the first SOFn (start-of-frame) marker and reads
/// its height/width fields — no full decode needed. Returns `null` if
/// [bytes] isn't a JPEG, is malformed, or the SOF marker falls outside
/// [bytes] (e.g. an unusually large EXIF block pushed it past the read
/// prefix) — any of which should fall back to the native reader.
(int, int)? _readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    final marker = bytes[offset + 1];

    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      offset += 2;
      if (marker == 0xD9) return null; // EOI
      continue;
    }
    if (marker == 0xDA) return null; // SOS — scan data follows, stop

    if (offset + 4 > bytes.length) return null;
    final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2) return null;

    final isSofMarker =
        (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSofMarker) {
      // Segment payload: [precision(1)][height(2)][width(2)]...
      final dataStart = offset + 4;
      if (dataStart + 5 > bytes.length) return null;
      final height = (bytes[dataStart + 1] << 8) | bytes[dataStart + 2];
      final width = (bytes[dataStart + 3] << 8) | bytes[dataStart + 4];
      return (width, height);
    }

    offset += 2 + segmentLength;
  }
  return null;
}

/// Reads width/height from a PNG's IHDR chunk at its fixed offset — no
/// decode needed. Returns `null` if [bytes] isn't a well-formed PNG.
(int, int)? _readPngDimensions(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  // bytes[8..11] = IHDR chunk length (always 13), bytes[12..15] = 'IHDR'.
  if (bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return null;
  }
  final width =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final height =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  return (width, height);
}
