import '../core/cancellation_token.dart';
import 'error_mapping.dart';
import 'messages.g.dart';

sealed class _TaskHandle {
  const _TaskHandle();
}

final class _NativeTaskHandle extends _TaskHandle {
  const _NativeTaskHandle();
}

final class _DartTaskHandle extends _TaskHandle {
  const _DartTaskHandle(this.token);
  final CancellationToken token;
}

/// Tracks every in-flight task Dart originates — both Dart-run (the pure
/// JPEG/PNG image engine, and the web image backend) and native-run
/// (video, WebP/HEIC, thumbnails, metadata) — so `PixelCompressor.tasks`
/// can answer `activeTaskIds()` entirely from Dart's own bookkeeping
/// (Dart always generates every `taskId` and holds the pending `Future`
/// for it, so it never needs to ask native what's running) and route
/// `cancel()` correctly per task kind: flip a [CancellationToken] for a
/// Dart-run task, or forward to the existing native `TaskHostApi` for a
/// native-run one.
class TaskRegistryDart {
  TaskRegistryDart._();
  static final TaskRegistryDart instance = TaskRegistryDart._();

  final Map<String, _TaskHandle> _tasks = {};
  final TaskHostApi _nativeApi = TaskHostApi();

  /// Registers a task whose actual work runs in native code — `cancel()`
  /// for this [taskId] will forward to the native `TaskHostApi`.
  void registerNative(String taskId) {
    _tasks[taskId] = const _NativeTaskHandle();
  }

  /// Registers a task whose work runs in Dart, returning the
  /// [CancellationToken] the caller must check at its own stage
  /// boundaries — `cancel()` for this [taskId] flips that token.
  CancellationToken registerDart(String taskId) {
    final token = CancellationToken();
    _tasks[taskId] = _DartTaskHandle(token);
    return token;
  }

  /// Must be called on every exit path (success, failure, or
  /// cancellation) once a task started with [registerNative]/[registerDart]
  /// is done, or it would otherwise appear active forever.
  void unregister(String taskId) {
    _tasks.remove(taskId);
  }

  /// Every task id currently registered, native- or Dart-run alike.
  List<String> get activeTaskIds => _tasks.keys.toList(growable: false);

  /// Returns `false` if [taskId] is unknown (already finished, or never
  /// existed) — matching the existing native `cancel()` contract.
  Future<bool> cancel(String taskId) async {
    final handle = _tasks[taskId];
    if (handle == null) return false;
    switch (handle) {
      case _DartTaskHandle(:final token):
        token.cancel();
        return true;
      case _NativeTaskHandle():
        return mapPlatformErrors(() => _nativeApi.cancel(taskId));
    }
  }

  /// Cancels every Dart-run task's token, then forwards to native
  /// `cancelAll()` only if at least one native-run task is registered —
  /// on web, nothing ever registers a native handle (there's no native
  /// channel there at all), so this must not call it unconditionally, or
  /// it would throw a `MissingPluginException` there.
  Future<void> cancelAll() async {
    var hasNativeTask = false;
    for (final handle in _tasks.values) {
      switch (handle) {
        case _DartTaskHandle(:final token):
          token.cancel();
        case _NativeTaskHandle():
          hasNativeTask = true;
      }
    }
    if (hasNativeTask) {
      await mapPlatformErrors(() => _nativeApi.cancelAll());
    }
  }
}
