import '../platform/error_mapping.dart';
import '../platform/messages.g.dart';

/// Cancellation and inspection of in-flight tasks — reachable as
/// `PixelCompressor.tasks`. The taskId comes from the `onProgress` events
/// a `compress`/`compressBatch` call reports.
class TaskManager {
  TaskManager.internal();

  final TaskHostApi _api = TaskHostApi();

  /// Cancels one task. Returns `false` if [taskId] was already finished or
  /// unknown. A cancelled task's `compress()` Future completes with
  /// [CompressionCancelledException].
  Future<bool> cancel(String taskId) =>
      mapPlatformErrors(() => _api.cancel(taskId));

  /// Cancels every in-flight task.
  Future<void> cancelAll() => mapPlatformErrors(() => _api.cancelAll());

  /// Task ids currently running.
  Future<List<String>> activeTaskIds() =>
      mapPlatformErrors(() => _api.activeTaskIds());
}
