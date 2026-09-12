import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/cancellation_token.dart';

void main() {
  test('starts not cancelled', () {
    final token = CancellationToken();
    expect(token.isCancelled, isFalse);
    expect(() => token.throwIfCancelled('t1'), returnsNormally);
  });

  test('cancel() flips isCancelled and throwIfCancelled throws', () {
    final token = CancellationToken()..cancel();
    expect(token.isCancelled, isTrue);
    expect(
      () => token.throwIfCancelled('t1'),
      throwsA(isA<CompressionCancelledException>()),
    );
  });

  test('cancel() is idempotent', () {
    final token = CancellationToken();
    token.cancel();
    token.cancel();
    expect(token.isCancelled, isTrue);
  });

  test('thrown exception carries the given taskId', () {
    final token = CancellationToken()..cancel();
    try {
      token.throwIfCancelled('my-task-42');
      fail('expected to throw');
    } on CompressionCancelledException catch (e) {
      expect(e.taskId, 'my-task-42');
      expect(e.nativeCode, 'cancelled');
    }
  });
}
