import Foundation

/// Tracks in-flight tasks so `TaskHostApi` can cancel them cooperatively.
///
/// Every HostApi call is dispatched onto `DispatchQueue.global` wrapped in
/// its own `DispatchWorkItem`, which is registered here under the request's
/// `taskId`. Engine code polls `isCancelled(taskId:)` at natural
/// checkpoints (per video sample, per thumbnail position, before/after
/// image encode) and throws `PixelCompressorError.cancelled()` when it
/// observes cancellation. All access is serialized through `queue` since
/// registration happens on background engine queues while `cancel`/
/// `cancelAll`/`activeTaskIds` are invoked from the Pigeon dispatch (main
/// thread).
final class TaskRegistry: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.therivanta.pixel_compressor.task_registry")
  private var workItems: [String: DispatchWorkItem] = [:]

  func register(taskId: String, workItem: DispatchWorkItem) {
    queue.sync { workItems[taskId] = workItem }
  }

  func unregister(taskId: String) {
    queue.sync { _ = workItems.removeValue(forKey: taskId) }
  }

  @discardableResult
  func cancel(taskId: String) -> Bool {
    queue.sync {
      guard let item = workItems[taskId] else { return false }
      item.cancel()
      return true
    }
  }

  func cancelAll() {
    queue.sync {
      for item in workItems.values {
        item.cancel()
      }
    }
  }

  func activeTaskIds() -> [String] {
    queue.sync { Array(workItems.keys) }
  }

  func isCancelled(taskId: String) -> Bool {
    queue.sync { workItems[taskId]?.isCancelled ?? false }
  }
}
