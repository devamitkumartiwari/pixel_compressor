import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/source_deletion.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pixel_compressor_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('deletes a real source file when output differs', () async {
    final source = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);
    final output = File('${tempDir.path}/output.jpg')..writeAsBytesSync([2]);

    await deleteSourceIfRequested(MediaSource.file(source), output.path);

    expect(source.existsSync(), isFalse);
    expect(output.existsSync(), isTrue);
  });

  test('does not delete when output path equals the source path (in-place compress)', () async {
    final source = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);

    await deleteSourceIfRequested(MediaSource.file(source), source.path);

    expect(source.existsSync(), isTrue);
  });

  test('does not delete when output path equals source via a relative/absolute mismatch', () async {
    final source = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);
    final relativeOutputPath = source.absolute.path;

    await deleteSourceIfRequested(MediaSource.file(source), relativeOutputPath);

    expect(source.existsSync(), isTrue);
  });

  test('is a no-op for MediaSource.bytes (no real source file)', () async {
    final output = File('${tempDir.path}/output.jpg')..writeAsBytesSync([2]);

    await expectLater(
      deleteSourceIfRequested(
        MediaSource.bytes(Uint8List.fromList([1])),
        output.path,
      ),
      completes,
    );
    expect(output.existsSync(), isTrue);
  });

  test('is a no-op for MediaSource.asset (no real source file)', () async {
    final output = File('${tempDir.path}/output.jpg')..writeAsBytesSync([2]);

    await expectLater(
      deleteSourceIfRequested(
        MediaSource.asset('assets/photo.jpg'),
        output.path,
      ),
      completes,
    );
    expect(output.existsSync(), isTrue);
  });

  test('swallows a delete failure instead of throwing', () async {
    final missingSource = File('${tempDir.path}/does_not_exist.jpg');
    final output = File('${tempDir.path}/output.jpg')..writeAsBytesSync([2]);

    await expectLater(
      deleteSourceIfRequested(MediaSource.file(missingSource), output.path),
      completes,
    );
  });
}
