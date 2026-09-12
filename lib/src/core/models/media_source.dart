import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Where a compression input comes from.
sealed class MediaSource {
  const MediaSource();

  /// Compress a [File] already resolved by the caller (e.g. from
  /// `image_picker`).
  const factory MediaSource.file(File file) = _FileSource;

  /// Compress the file at [path].
  const factory MediaSource.path(String path) = _PathSource;

  /// Compress in-memory [bytes] (e.g. a network response, or bytes read
  /// from a picker) without the caller having to manage a temp [File].
  ///
  /// [fileExtensionHint] (e.g. `'jpg'`, `'mp4'`) is only consulted when this
  /// source must be materialized to a temp file for a file/URL-based
  /// native call (video, thumbnails, metadata) — image compression on
  /// non-web platforms decodes bytes directly with no temp file.
  const factory MediaSource.bytes(
    Uint8List bytes, {
    String? fileExtensionHint,
  }) = _BytesSource;

  /// Compress a Flutter asset bundled with the app.
  const factory MediaSource.asset(String assetName, {AssetBundle? bundle}) =
      _AssetSource;

  /// The resolved filesystem path this source points to.
  ///
  /// Throws [UnsupportedError] for [MediaSource.bytes] and
  /// [MediaSource.asset] — prefer [filePath], which is `null` instead of
  /// throwing for those variants.
  String get resolvedPath;

  /// The resolved filesystem path, or `null` for [MediaSource.bytes] and
  /// [MediaSource.asset] (which have no path until materialized).
  String? get filePath;

  /// A best-effort file extension (no dot, e.g. `'jpg'`) for a source with
  /// no real path — used only when this source must be materialized to a
  /// temp file. `null` for [MediaSource.file]/`.path` (their real
  /// extension is taken from the path itself instead).
  String? get fileExtensionHint;

  /// Reads this source's full content into memory. For [MediaSource.file]
  /// and [MediaSource.path] this reads the file from disk; for
  /// [MediaSource.bytes] it returns the bytes as-is; for
  /// [MediaSource.asset] it loads from the asset bundle.
  Future<Uint8List> readBytes();
}

final class _FileSource extends MediaSource {
  const _FileSource(this.file);

  final File file;

  @override
  String get resolvedPath => file.path;

  @override
  String? get filePath => file.path;

  @override
  String? get fileExtensionHint => null;

  @override
  Future<Uint8List> readBytes() => file.readAsBytes();
}

final class _PathSource extends MediaSource {
  const _PathSource(this.path);

  final String path;

  @override
  String get resolvedPath => path;

  @override
  String? get filePath => path;

  @override
  String? get fileExtensionHint => null;

  @override
  Future<Uint8List> readBytes() => File(path).readAsBytes();
}

final class _BytesSource extends MediaSource {
  const _BytesSource(this.bytes, {this.fileExtensionHint});

  final Uint8List bytes;

  @override
  final String? fileExtensionHint;

  @override
  String get resolvedPath => throw UnsupportedError(
    'MediaSource.bytes has no resolvedPath; use filePath.',
  );

  @override
  String? get filePath => null;

  @override
  Future<Uint8List> readBytes() async => bytes;
}

final class _AssetSource extends MediaSource {
  const _AssetSource(this.assetName, {this.bundle});

  final String assetName;
  final AssetBundle? bundle;

  @override
  String get resolvedPath => throw UnsupportedError(
    'MediaSource.asset has no resolvedPath; use filePath.',
  );

  @override
  String? get filePath => null;

  @override
  String? get fileExtensionHint {
    final dot = assetName.lastIndexOf('.');
    if (dot < 0 || dot == assetName.length - 1) return null;
    return assetName.substring(dot + 1);
  }

  @override
  Future<Uint8List> readBytes() async {
    final data = await (bundle ?? rootBundle).load(assetName);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
