import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/platform/file_prefix_reader.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pixel_compressor_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'file source: reads only the requested prefix, reports true total size',
    () async {
      final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final file = File('${tempDir.path}/big.bin')..writeAsBytesSync(bytes);

      final prefix = await readSourcePrefix(
        MediaSource.file(file),
        maxBytes: 100,
      );

      expect(prefix.bytes.length, 100);
      expect(prefix.bytes, bytes.sublist(0, 100));
      expect(prefix.totalSizeBytes, 1000);
    },
  );

  test('file source smaller than maxBytes returns the whole file', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final file = File('${tempDir.path}/small.bin')..writeAsBytesSync(bytes);

    final prefix = await readSourcePrefix(
      MediaSource.file(file),
      maxBytes: 100,
    );

    expect(prefix.bytes, bytes);
    expect(prefix.totalSizeBytes, 5);
  });

  test(
    'bytes source: caps the returned prefix but reports true total size',
    () async {
      final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));

      final prefix = await readSourcePrefix(
        MediaSource.bytes(bytes),
        maxBytes: 100,
      );

      expect(prefix.bytes.length, 100);
      expect(prefix.totalSizeBytes, 1000);
    },
  );

  test('bytes source smaller than maxBytes returns everything', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final prefix = await readSourcePrefix(
      MediaSource.bytes(bytes),
      maxBytes: 100,
    );

    expect(prefix.bytes, bytes);
    expect(prefix.totalSizeBytes, 3);
  });
}
