import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/cache_manager.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.cachePath);
  final String cachePath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fakeOsCacheDir;
  late CacheManager cacheManager;

  setUp(() {
    fakeOsCacheDir = Directory.systemTemp.createTempSync(
      'pixel_compressor_os_cache_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      fakeOsCacheDir.path,
    );
    cacheManager = CacheManager.internal();
  });

  tearDown(() {
    if (fakeOsCacheDir.existsSync()) fakeOsCacheDir.deleteSync(recursive: true);
  });

  test('resolveOutputPath lands under <cacheDir>/pixel_compressor/<kind>', () async {
    final path = await cacheManager.resolveOutputPath(CacheKind.images, 'jpg');
    expect(
      path,
      contains(
        '${Platform.pathSeparator}pixel_compressor${Platform.pathSeparator}images${Platform.pathSeparator}',
      ),
    );
    expect(path, endsWith('.jpg'));
    expect(path.startsWith(fakeOsCacheDir.path), isTrue);
  });

  test('resolveOutputPath returns a distinct path on every call', () async {
    final a = await cacheManager.resolveOutputPath(CacheKind.videos, 'mp4');
    final b = await cacheManager.resolveOutputPath(CacheKind.videos, 'mp4');
    expect(a, isNot(b));
  });

  test(
    'size() is 0 before anything is written, then reflects written bytes',
    () async {
      expect(await cacheManager.size(), 0);

      final path = await cacheManager.resolveOutputPath(
        CacheKind.thumbnails,
        'png',
      );
      await File(path).writeAsBytes(List.filled(500, 1));

      expect(await cacheManager.size(), 500);
    },
  );

  test('size() sums across every kind subdirectory', () async {
    final imagePath = await cacheManager.resolveOutputPath(
      CacheKind.images,
      'jpg',
    );
    await File(imagePath).writeAsBytes(List.filled(100, 1));
    final videoPath = await cacheManager.resolveOutputPath(
      CacheKind.videos,
      'mp4',
    );
    await File(videoPath).writeAsBytes(List.filled(200, 1));

    expect(await cacheManager.size(), 300);
  });

  test('clear() removes everything and size() returns to 0', () async {
    final path = await cacheManager.resolveOutputPath(CacheKind.images, 'jpg');
    await File(path).writeAsBytes(List.filled(50, 1));
    expect(await cacheManager.size(), 50);

    await cacheManager.clear();

    expect(await cacheManager.size(), 0);
    expect(File(path).existsSync(), isFalse);
  });

  test(
    'resolveOutputPath still works after clear() (root recreated)',
    () async {
      await cacheManager.clear();
      final path = await cacheManager.resolveOutputPath(
        CacheKind.images,
        'jpg',
      );
      await File(path).writeAsBytes([1]);
      expect(File(path).existsSync(), isTrue);
    },
  );
}
