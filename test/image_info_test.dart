import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/image/image_compress_mobile.dart';

Uint8List _bytes(List<int> b) => .fromList(b);
List<int> _be16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];
List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le24(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF];
List<int> _ascii(String s) => s.codeUnits;

Uint8List _png(int w, int h) => _bytes([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ..._be32(13),
  ..._ascii('IHDR'),
  ..._be32(w),
  ..._be32(h),
  8,
  6,
  0,
  0,
  0,
]);

/// JPEG with an optional big-endian EXIF APP1 orientation and an SOF0.
Uint8List _jpeg(int w, int h, {int? orientation}) {
  final app1 = <int>[];
  if (orientation != null) {
    final tiff = [
      ..._ascii('MM'), ..._be16(42), ..._be32(8), // header, IFD at 8
      ..._be16(1), // one entry
      ..._be16(0x0112), ..._be16(3), ..._be32(1), ..._be16(orientation), 0, 0,
      ..._be32(0),
    ];
    final payload = [..._ascii('Exif'), 0, 0, ...tiff];
    app1.addAll([0xFF, 0xE1, ..._be16(payload.length + 2), ...payload]);
  }
  return _bytes([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    ..._be16(16),
    ..._ascii('JFIF'),
    0,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
    ...app1,
    0xFF,
    0xC0,
    ..._be16(17),
    8,
    ..._be16(h),
    ..._be16(w),
    3,
    1,
    0x22,
    0,
    2,
    0x11,
    1,
    3,
    0x11,
    1,
    0xFF,
    0xD9,
  ]);
}

Uint8List _webp(String chunk, List<int> payload) => _bytes([
  ..._ascii('RIFF'),
  0,
  0,
  0,
  0,
  ..._ascii('WEBP'),
  ..._ascii(chunk),
  ..._le16(payload.length),
  0,
  0,
  ...payload,
]);

List<int> _box(String type, List<int> body) => [
  ..._be32(body.length + 8),
  ..._ascii(type),
  ...body,
];

Uint8List _heic(List<(int, int)> sizes, {int irot = 0}) => _bytes([
  ..._box('ftyp', [..._ascii('heic'), 0, 0, 0, 0, ..._ascii('mif1heic')]),
  ..._box('meta', [
    0, 0, 0, 0, // version + flags
    ..._box('iprp', [
      ..._box('ipco', [
        for (final (w, h) in sizes)
          ..._box('ispe', [0, 0, 0, 0, ..._be32(w), ..._be32(h)]),
        ..._box('irot', [irot]),
      ]),
    ]),
  ]),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PixelImageInfo.fromBytes', () {
    test('PNG', () {
      final info = PixelImageInfo.fromBytes(_png(640, 480))!;
      expect(
        (info.width, info.height, info.format),
        (640, 480, PixelImageFormat.png),
      );
    });

    test('JPEG', () {
      final info = PixelImageInfo.fromBytes(_jpeg(3000, 2000))!;
      expect(
        (info.width, info.height, info.format),
        (3000, 2000, PixelImageFormat.jpeg),
      );
      expect(info.orientation, 1);
    });

    test('JPEG with EXIF orientation 6 reports the displayed size', () {
      final info = PixelImageInfo.fromBytes(_jpeg(4000, 3000, orientation: 6))!;
      expect((info.width, info.height, info.orientation), (3000, 4000, 6));
    });

    test('JPEG with EXIF orientation 3 keeps the axes', () {
      final info = PixelImageInfo.fromBytes(_jpeg(4000, 3000, orientation: 3))!;
      expect((info.width, info.height), (4000, 3000));
    });

    test('WebP VP8 (lossy)', () {
      final payload = [0, 0, 0, 0x9D, 0x01, 0x2A, ..._le16(800), ..._le16(600)];
      final info = PixelImageInfo.fromBytes(_webp('VP8 ', payload))!;
      expect(
        (info.width, info.height, info.format),
        (800, 600, PixelImageFormat.webp),
      );
    });

    test('WebP VP8L (lossless)', () {
      // width-1 = 299, height-1 = 199 packed in 14-bit fields.
      const w1 = 299, h1 = 199;
      final bits = w1 | (h1 << 14);
      final payload = [
        0x2F,
        bits & 0xFF,
        (bits >> 8) & 0xFF,
        (bits >> 16) & 0xFF,
        (bits >> 24) & 0xFF,
      ];
      final info = PixelImageInfo.fromBytes(_webp('VP8L', payload))!;
      expect((info.width, info.height), (300, 200));
    });

    test('WebP VP8X (extended)', () {
      final payload = [0, 0, 0, 0, ..._le24(1919), ..._le24(1079)];
      final info = PixelImageInfo.fromBytes(_webp('VP8X', payload))!;
      expect((info.width, info.height), (1920, 1080));
    });

    test('HEIC picks the largest ispe (not the thumbnail)', () {
      final info = PixelImageInfo.fromBytes(_heic([(320, 240), (4032, 3024)]))!;
      expect(
        (info.width, info.height, info.format),
        (4032, 3024, PixelImageFormat.heic),
      );
    });

    test('HEIC irot swaps axes', () {
      final info = PixelImageInfo.fromBytes(_heic([(4032, 3024)], irot: 3))!;
      expect((info.width, info.height, info.orientation), (3024, 4032, 6));
    });

    test('unknown or truncated input returns null instead of throwing', () {
      expect(PixelImageInfo.fromBytes(_bytes(List.filled(64, 7))), isNull);
      expect(PixelImageInfo.fromBytes(_jpeg(10, 10).sublist(0, 24)), isNull);
      expect(PixelImageInfo.fromBytes(_png(10, 10).sublist(0, 10)), isNull);
    });
  });

  group('batch + info', () {
    const channel = MethodChannel('pixel_compressor/image');
    late Directory tmp;

    setUp(() {
      PixelImageCompressMobile.registerWith();
      PixelImageCompressor.ignoreCheckSupportPlatform(true);
      tmp = .systemTemp.createTempSync('pc_batch');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final path = (call.arguments as List)[0] as String;
            if (path.contains('bad')) {
              throw PlatformException(
                code: 'decode_failed',
                message: 'bad file',
              );
            }
            await Future<void>.delayed(
              Duration(milliseconds: path.contains('slow') ? 30 : 1),
            );
            return _jpeg(200, 100);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      tmp.deleteSync(recursive: true);
    });

    String file(String name) =>
        (File('${tmp.path}/$name')..writeAsBytesSync([1])).path;

    test('compressFileWithInfo returns the output size', () async {
      final result = await PixelImageCompressor.compressFileWithInfo(
        file('a.jpg'),
      );
      expect((result.info.width, result.info.height), (200, 100));
    });

    test('keeps input order and isolates failures', () async {
      final paths = [
        file('slow.jpg'),
        file('bad.jpg'),
        file('c.jpg'),
        '${tmp.path}/missing.jpg',
      ];
      final progress = <int>[];
      final items = await PixelImageCompressor.compressFilesToBytes(
        paths,
        concurrency: 3,
        onProgress: (done, total) {
          expect(total, 4);
          progress.add(done);
        },
      );
      expect(items.map((e) => e.path), paths);
      expect(items.map((e) => e.isSuccess), [true, false, true, false]);
      expect(items[1].error!.code, 'decode_failed');
      expect(items[0].info!.width, 200);
      expect(progress, [1, 2, 3, 4]);
    });
  });
}
