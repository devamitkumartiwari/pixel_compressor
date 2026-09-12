import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

void main() {
  group('MediaSource.file/.path', () {
    test('filePath and resolvedPath agree', () {
      final file = MediaSource.file(File('/tmp/a.jpg'));
      expect(file.filePath, '/tmp/a.jpg');
      expect(file.resolvedPath, '/tmp/a.jpg');

      final path = MediaSource.path('/tmp/b.jpg');
      expect(path.filePath, '/tmp/b.jpg');
      expect(path.resolvedPath, '/tmp/b.jpg');
    });

    test('readBytes reads the real file', () async {
      final dir = Directory.systemTemp.createTempSync('pixel_compressor_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/x.bin')..writeAsBytesSync([1, 2, 3]);

      final bytes = await MediaSource.file(file).readBytes();
      expect(bytes, [1, 2, 3]);
    });
  });

  group('MediaSource.bytes', () {
    test('filePath is null, resolvedPath throws', () {
      final source = MediaSource.bytes(Uint8List.fromList([1, 2, 3]));
      expect(source.filePath, isNull);
      expect(() => source.resolvedPath, throwsUnsupportedError);
    });

    test('readBytes returns the bytes as-is', () async {
      final data = Uint8List.fromList([9, 8, 7]);
      final source = MediaSource.bytes(data);
      expect(await source.readBytes(), same(data));
    });

    test('fileExtensionHint is whatever was passed', () {
      final source = MediaSource.bytes(Uint8List(0), fileExtensionHint: 'mp4');
      expect(source.fileExtensionHint, 'mp4');
      expect(MediaSource.bytes(Uint8List(0)).fileExtensionHint, isNull);
    });
  });

  group('MediaSource.asset', () {
    test('filePath is null, resolvedPath throws', () {
      final source = MediaSource.asset('assets/photo.jpg');
      expect(source.filePath, isNull);
      expect(() => source.resolvedPath, throwsUnsupportedError);
    });

    test('fileExtensionHint is derived from the asset name', () {
      expect(MediaSource.asset('assets/photo.jpg').fileExtensionHint, 'jpg');
      expect(MediaSource.asset('assets/clip.mp4').fileExtensionHint, 'mp4');
      expect(
        MediaSource.asset('assets/no_extension').fileExtensionHint,
        isNull,
      );
      expect(MediaSource.asset('assets/trailing.').fileExtensionHint, isNull);
    });
  });
}
