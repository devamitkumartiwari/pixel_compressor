import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trimEnd <= trimStart throws InvalidMediaException synchronously, '
      'before any platform channel call', () async {
    await expectLater(
      PixelCompressor.video.compress(
        MediaSource.path('/does/not/exist.mp4'),
        options: const VideoCompressOptions(
          trimStart: Duration(seconds: 5),
          trimEnd: Duration(seconds: 5),
        ),
      ),
      throwsA(isA<InvalidMediaException>()),
    );

    await expectLater(
      PixelCompressor.video.compress(
        MediaSource.path('/does/not/exist.mp4'),
        options: const VideoCompressOptions(
          trimStart: Duration(seconds: 5),
          trimEnd: Duration(seconds: 4),
        ),
      ),
      throwsA(isA<InvalidMediaException>()),
    );
  });

  test(
    'trimEnd > trimStart does not throw the trim-ordering exception',
    () async {
      // No platform channel is registered in a plain unit test, so this will
      // still fail — but it must fail with something other than the trim
      // ordering check, proving that check passed and execution moved on
      // (to attempting the — here, unregistered — platform call).
      await expectLater(
        PixelCompressor.video.compress(
          MediaSource.path('/does/not/exist.mp4'),
          options: const VideoCompressOptions(
            trimStart: Duration(seconds: 1),
            trimEnd: Duration(seconds: 5),
          ),
        ),
        throwsA(isNot(isA<InvalidMediaException>())),
      );
    },
  );
}
