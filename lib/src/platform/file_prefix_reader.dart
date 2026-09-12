import 'dart:io';
import 'dart:typed_data';

import '../core/models/media_source.dart';

/// A bounded prefix of a [MediaSource]'s bytes, plus its true total size.
class SourcePrefix {
  const SourcePrefix({required this.bytes, required this.totalSizeBytes});

  /// At most the first `maxBytes` requested — never the whole source for
  /// a large `.file`/`.path` source.
  final Uint8List bytes;

  /// The source's real total size, regardless of how much of [bytes] was
  /// actually read.
  final int totalSizeBytes;
}

/// Reads at most [maxBytes] of [input] cheaply — a bounded partial read
/// for `.file`/`.path` (via `RandomAccessFile`, never loading the whole
/// file just to inspect its header) and the already-in-memory/loaded
/// bytes as-is (capped defensively) for `.bytes`/`.asset`, which have no
/// cheaper alternative since they must be fully read/loaded anyway.
Future<SourcePrefix> readSourcePrefix(
  MediaSource input, {
  int maxBytes = 128 * 1024,
}) async {
  final path = input.filePath;
  if (path == null) {
    final fullBytes = await input.readBytes();
    final prefix = fullBytes.length <= maxBytes
        ? fullBytes
        : fullBytes.sublist(0, maxBytes);
    return SourcePrefix(bytes: prefix, totalSizeBytes: fullBytes.length);
  }

  final file = File(path);
  final totalSize = await file.length();
  final raf = await file.open();
  try {
    final toRead = totalSize < maxBytes ? totalSize : maxBytes;
    final prefix = await raf.read(toRead);
    return SourcePrefix(bytes: prefix, totalSizeBytes: totalSize);
  } finally {
    await raf.close();
  }
}
