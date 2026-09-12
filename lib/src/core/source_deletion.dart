import 'dart:io';

import 'models/media_source.dart';

/// Deletes [input]'s real source file after a successful compress, when
/// requested via `deleteSourceOnSuccess`. A no-op for [MediaSource.bytes]
/// and [MediaSource.asset] (no real source file to delete), and for an
/// in-place compress where the output was written back over the source.
/// Delete failures are swallowed — the compress already succeeded, so a
/// locked/permission-denied source file shouldn't surface as an error on
/// an otherwise-successful call.
Future<void> deleteSourceIfRequested(
  MediaSource input,
  String outputPath,
) async {
  final sourcePath = input.filePath;
  if (sourcePath == null) return;
  try {
    if (File(sourcePath).absolute.path == File(outputPath).absolute.path) {
      return;
    }
    final file = File(sourcePath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best-effort only.
  }
}
