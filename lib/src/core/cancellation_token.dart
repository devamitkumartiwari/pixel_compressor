import 'exceptions/pixel_compressor_exception.dart';

/// A cooperative cancellation flag for a Dart-run task (currently: the
/// pure-Dart JPEG/PNG image engine). Checked at stage boundaries the same
/// way native engines check `ensureActive()`/`isCancelled()` — this
/// package doesn't have coroutine-style preemptive cancellation for plain
/// async Dart code, so cancellation only takes effect at the next
/// checkpoint, not instantly.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  /// Throws [CompressionCancelledException] if [cancel] has been called.
  void throwIfCancelled(String taskId) {
    if (_cancelled) {
      throw CompressionCancelledException(
        nativeCode: 'cancelled',
        nativeMessage: 'Task $taskId was cancelled.',
        taskId: taskId,
      );
    }
  }
}
