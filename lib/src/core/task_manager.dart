import '../platform/task_registry_dart.dart';

/// Cancellation and inspection of in-flight tasks — reachable as
/// `PixelCompressor.tasks`. The taskId comes from the `onProgress` events
/// a `compress`/`compressBatch` call reports.
///
/// Backed entirely by [TaskRegistryDart] — Dart originates every task id
/// and holds the pending `Future` for it, native- or Dart-run alike, so
/// this never needs its own platform channel call; `cancel()`/`cancelAll()`
/// forward to native only for the tasks that actually need it.
class TaskManager {
  TaskManager.internal();

  /// Cancels one task. Returns `false` if [taskId] was already finished or
  /// unknown. A cancelled task's `compress()` Future completes with
  /// [CompressionCancelledException].
  Future<bool> cancel(String taskId) =>
      TaskRegistryDart.instance.cancel(taskId);

  /// Cancels every in-flight task.
  Future<void> cancelAll() => TaskRegistryDart.instance.cancelAll();

  /// Task ids currently running.
  Future<List<String>> activeTaskIds() async =>
      TaskRegistryDart.instance.activeTaskIds;
}
