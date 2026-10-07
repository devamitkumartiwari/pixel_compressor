import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/image/image_compress_macos.dart';
import 'package:pixel_compressor/src/image/image_compress_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pixel_compressor/image');
  final calls = <MethodCall>[];
  late Directory tmp;
  late String srcPath;

  setUp(() {
    PixelImageCompressMobile.registerWith();
    PixelImageCompressor.ignoreCheckSupportPlatform(true);
    calls.clear();
    tmp = .systemTemp.createTempSync('pixel_compressor_test');
    srcPath = '${tmp.path}/src.jpg';
    File(srcPath).writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'compressWithList':
            case 'compressWithFile':
              return Uint8List.fromList([1, 2, 3]);
            case 'compressWithFileAndGetFile':
              return (call.arguments as List)[4];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  test('compressBytes sends compressWithList with base args', () async {
    final result = await PixelImageCompressor.compressBytes(
      Uint8List.fromList([9, 9]),
      minWidth: 100,
      minHeight: 50,
      quality: 70,
      rotate: 90,
      format: PixelImageFormat.png,
      keepExif: true,
    );
    expect(result, [1, 2, 3]);
    expect(calls.single.method, 'compressWithList');
    final args = calls.single.arguments as List;
    expect(args.sublist(1), [
      100,
      50,
      70,
      90,
      true,
      1,
      true,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
  });

  test('compressFileToBytes sends compressWithFile', () async {
    await PixelImageCompressor.compressFileToBytes(srcPath, quality: 60);
    expect(calls.single.method, 'compressWithFile');
    final args = calls.single.arguments as List;
    expect(args, [
      srcPath,
      1920,
      1080,
      60,
      0,
      true,
      0,
      false,
      1,
      5,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
  });

  test('compressFileToFile returns the target as XFile', () async {
    final target = '${tmp.path}/out.webp';
    final file = await PixelImageCompressor.compressFileToFile(
      srcPath,
      target,
      format: PixelImageFormat.webp,
    );
    expect(calls.single.method, 'compressWithFileAndGetFile');
    expect(file.path, target);
  });

  test('compressFileToFile rejects same source and target', () {
    expect(
      () => PixelImageCompressor.compressFileToFile(srcPath, srcPath),
      throwsArgumentError,
    );
  });

  test('missing source file throws PixelCompressError', () {
    expect(
      () => PixelImageCompressor.compressFileToBytes('${tmp.path}/nope.jpg'),
      throwsA(isA<PixelCompressError>()),
    );
  });

  test('native errors surface as PixelCompressError with code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'decode_failed', message: 'bad');
        });
    await expectLater(
      PixelImageCompressor.compressBytes(Uint8List.fromList([1])),
      throwsA(
        isA<PixelCompressError>().having(
          (e) => e.code,
          'code',
          'decode_failed',
        ),
      ),
    );
  });

  test('maxWidth/maxHeight/exactSize are appended after base args', () async {
    await PixelImageCompressor.compressFileToBytes(
      srcPath,
      maxWidth: 800,
      maxHeight: 600,
    );
    await PixelImageCompressor.compressBytes(
      Uint8List.fromList([1]),
      exactSize: const PixelExactSize(
        300,
        200,
        fit: .cover,
        padColor: 0xFFFFFFFF,
      ),
    );
    final fileArgs = calls[0].arguments as List;
    expect(fileArgs.sublist(10), [800, 600, 0, 0, 0, 0]);
    final listArgs = calls[1].arguments as List;
    expect(listArgs.sublist(9), [0, 0, 300, 200, 2, 0xFFFFFFFF]);
  });

  test('null native results throw instead of returning null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    await expectLater(
      PixelImageCompressor.compressFileToBytes(srcPath),
      throwsA(isA<PixelCompressError>()),
    );
    await expectLater(
      PixelImageCompressor.compressFileToFile(srcPath, '${tmp.path}/o.jpg'),
      throwsA(isA<PixelCompressError>()),
    );
  });

  group('validator', () {
    test('rejects mismatched target extension', () {
      final validator = PixelImageFormatValidator(channel);
      expect(
        () => validator.checkFileNameAndFormat('a.png', .jpeg),
        throwsA(anything),
      );
    });

    test('accepts matching extensions, case-insensitive', () {
      final validator = PixelImageFormatValidator(channel);
      validator.checkFileNameAndFormat('a.JPEG', .jpeg);
      validator.checkFileNameAndFormat('a.webp', .webp);
      validator.checkFileNameAndFormat('a.heic', .heic);
    });

    test('ignoreCheckExtName bypasses the check', () {
      final validator = PixelImageFormatValidator(channel)
        ..ignoreCheckExtName = true;
      validator.checkFileNameAndFormat('a.png', .jpeg);
    });

    test('every format is supported on Android and iOS', () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final validator = PixelImageFormatValidator(channel);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        for (final format in PixelImageFormat.values) {
          expect(await validator.checkSupportPlatform(format), isTrue);
        }
      }
    });

    test('unsupported formats throw unsupported_format', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final validator = PixelImageFormatValidator(channel);
      expect(await validator.checkSupportPlatform(.jpeg), isTrue);
      await expectLater(
        validator.checkSupportPlatform(.heic),
        throwsA(
          isA<PixelCompressError>().having(
            (e) => e.code,
            'code',
            'unsupported_format',
          ),
        ),
      );
    });

    test('macOS rejects WebP with unsupported_format', () async {
      final macos = PixelImageCompressMacos();
      expect(await macos.validator.checkSupportPlatform(.heic), isTrue);
      await expectLater(
        macos.checkSupport(.webp),
        throwsA(
          isA<PixelCompressError>().having(
            (e) => e.code,
            'code',
            'unsupported_format',
          ),
        ),
      );
    });
  });
}
