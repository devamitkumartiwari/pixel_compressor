import 'dart:io';

/// Where a compression input comes from.
///
/// Only [MediaSource.file] and [MediaSource.path] are supported in this
/// release — in-memory `MediaSource.bytes` compression is planned for a
/// follow-up release (it needs a small native-side change to accept raw
/// bytes without an extra Dart-side temp-file write; see the CHANGELOG).
sealed class MediaSource {
  const MediaSource();

  /// Compress a [File] already resolved by the caller (e.g. from
  /// `image_picker`).
  const factory MediaSource.file(File file) = _FileSource;

  /// Compress the file at [path].
  const factory MediaSource.path(String path) = _PathSource;

  /// The resolved filesystem path this source points to.
  String get resolvedPath;
}

final class _FileSource extends MediaSource {
  const _FileSource(this.file);

  final File file;

  @override
  String get resolvedPath => file.path;
}

final class _PathSource extends MediaSource {
  const _PathSource(this.path);

  final String path;

  @override
  String get resolvedPath => path;
}
