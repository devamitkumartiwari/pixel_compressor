import '../core/models/media_source.dart';
import 'bytes_materializer.dart';

/// Resolves any [MediaSource] to a real filesystem path for the existing
/// path-based native calls, materializing [MediaSource.bytes]/`.asset` to
/// a task-scoped temp file when needed. [MediaSource.file]/`.path` resolve
/// with no I/O and nothing to clean up.
///
/// Always call [cleanup] in a `finally`, on every exit path (success,
/// thrown `PixelCompressorException`, or cancellation) — it is a no-op for
/// `.file`/`.path` sources and deletes the temp file/dir for the others.
class MaterializedSource {
  const MaterializedSource._(this.path, this._tempPath);

  final String path;
  final String? _tempPath;

  static Future<MaterializedSource> resolve(
    MediaSource input, {
    required String taskId,
    String defaultExtensionHint = 'tmp',
  }) async {
    final existingPath = input.filePath;
    if (existingPath != null) {
      return MaterializedSource._(existingPath, null);
    }

    final bytes = await input.readBytes();
    final tempPath = await materializeBytesToTempFile(
      bytes,
      taskId: taskId,
      extensionHint: input.fileExtensionHint ?? defaultExtensionHint,
    );
    return MaterializedSource._(tempPath, tempPath);
  }

  Future<void> cleanup() async {
    final tempPath = _tempPath;
    if (tempPath != null) {
      await deleteMaterializedTempFile(tempPath);
    }
  }
}
