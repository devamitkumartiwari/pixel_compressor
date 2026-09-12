import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] to a fresh, task-scoped temp file so an existing
/// path-based native call can consume it unchanged. The caller is
/// responsible for deleting the returned file's parent directory in a
/// `finally`, on every exit path — success, native failure, or
/// cancellation.
Future<String> materializeBytesToTempFile(
  Uint8List bytes, {
  required String taskId,
  String extensionHint = 'tmp',
}) async {
  final dir = await Directory.systemTemp.createTemp(
    'pixel_compressor_${taskId}_',
  );
  final file = File(
    '${dir.path}${Platform.pathSeparator}source.$extensionHint',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Deletes the temp directory created by [materializeBytesToTempFile] for
/// [materializedPath]. Best-effort — failures are swallowed, since this
/// only ever cleans up pixel_compressor's own scratch files.
Future<void> deleteMaterializedTempFile(String materializedPath) async {
  try {
    final parentDir = File(materializedPath).parent;
    if (await parentDir.exists()) {
      await parentDir.delete(recursive: true);
    }
  } catch (_) {
    // Best-effort cleanup only.
  }
}
