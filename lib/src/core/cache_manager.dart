import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'exceptions/pixel_compressor_exception.dart';

/// The plugin-owned cache subtree kinds, each a subdirectory under the
/// resolved cache root — matches the native `CacheKind`/`Kind` naming
/// exactly (Android's `CacheManager.kt`, iOS/macOS's `CacheManager.swift`),
/// since those directories are shared: whichever engine (Dart or native)
/// wrote a file, [CacheManager.size]/[CacheManager.clear] account for it.
enum CacheKind {
  images('images'),
  videos('videos'),
  thumbnails('thumbnails');

  const CacheKind(this.dirName);
  final String dirName;
}

/// Management of pixel_compressor's own output cache directory —
/// reachable as `PixelCompressor.cache`. Only applies to results written
/// without an explicit `outputPath`.
///
/// Pure Dart: resolves the same OS cache directory
/// (`context.getCacheDir()` on Android, `NSCachesDirectory` on iOS/macOS)
/// the native engines use internally for their own WebP/HEIC/video
/// output, via `path_provider` — so this stays a single, shared, byte-for-
/// byte-identical cache tree no matter which engine wrote into it.
///
/// Not supported on web — [size]/[clear]/[resolveOutputPath] throw
/// [PlatformNotSupportedException] there (a web compress result has no
/// backing file at all; see `CompressionResult.outputBytes`, and
/// `path_provider` itself has no cache directory concept on web).
class CacheManager {
  CacheManager.internal();

  Directory? _root;
  int _uniqueNameCounter = 0;

  /// Total bytes currently used by cached compression output.
  Future<int> size() async {
    _throwIfWeb();
    final root = await _resolveRoot();
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Deletes every cached output file.
  Future<void> clear() async {
    _throwIfWeb();
    final root = await _resolveRoot();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
  }

  /// Resolves a fresh output path for a new file of [kind] with the given
  /// [extension] (no leading dot) inside the cache-managed subtree —
  /// used when a compress request's `outputPath` is null.
  Future<String> resolveOutputPath(CacheKind kind, String extension) async {
    _throwIfWeb();
    final dir = await _resolveKindDir(kind);
    final name = '${_uniqueName()}.$extension';
    return '${dir.path}${Platform.pathSeparator}$name';
  }

  Future<Directory> _resolveKindDir(CacheKind kind) async {
    final root = await _resolveRoot();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}${kind.dirName}',
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _resolveRoot() async {
    final cached = _root;
    if (cached != null) return cached;
    final cacheDir = await getApplicationCacheDirectory();
    final root = Directory(
      '${cacheDir.path}${Platform.pathSeparator}pixel_compressor',
    );
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    _root = root;
    return root;
  }

  String _uniqueName() {
    _uniqueNameCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}_$_uniqueNameCounter';
  }

  void _throwIfWeb() {
    if (kIsWeb) {
      throw const PlatformNotSupportedException(
        nativeCode: 'platform_not_supported',
        nativeMessage: 'PixelCompressor.cache is not supported on web.',
      );
    }
  }
}
