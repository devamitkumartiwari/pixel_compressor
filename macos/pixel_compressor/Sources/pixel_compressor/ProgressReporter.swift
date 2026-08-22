import Foundation

/// Wraps the generated `PixelCompressorProgressCallbackApi` FlutterApi
/// caller: hops every call to the main thread (required for Pigeon
/// FlutterApi callers) and throttles `onProgress` emissions to at least a
/// 1-point percent delta per task so a tight sample-processing loop
/// doesn't flood the platform channel.
final class ProgressReporter: @unchecked Sendable {
  private let api: PixelCompressorProgressCallbackApi
  private let queue = DispatchQueue(label: "com.therivanta.pixel_compressor.progress_reporter")
  private var lastPercent: [String: Double] = [:]

  init(api: PixelCompressorProgressCallbackApi) {
    self.api = api
  }

  /// Reports progress for `taskId`. Pass `force: true` to bypass the
  /// throttle (used for stage-boundary events like `preparing`/`completed`
  /// that must always be observed even if the percent delta is small).
  func reportProgress(
    taskId: String,
    stage: CompressionStageWire,
    percent: Double,
    currentItemIndex: Int64? = nil,
    totalItems: Int64? = nil,
    note: String? = nil,
    force: Bool = false
  ) {
    let clamped = min(max(percent, 0), 100)
    let shouldSend: Bool = queue.sync {
      let last = lastPercent[taskId]
      if force || last == nil || abs(clamped - last!) >= 1 || clamped == 100 {
        lastPercent[taskId] = clamped
        return true
      }
      return false
    }
    guard shouldSend else { return }

    let event = ProgressEventMessage(
      taskId: taskId,
      stage: stage,
      percent: clamped,
      currentItemIndex: currentItemIndex,
      totalItems: totalItems,
      note: note
    )
    let api = self.api
    DispatchQueue.main.async {
      api.onProgress(event: event) { _ in }
    }
  }

  /// Reports the single terminal event for `taskId`. Callers must ensure
  /// this is invoked exactly once per task, matching the outcome of the
  /// Pigeon `completion` handler.
  func reportTerminal(
    taskId: String,
    outcome: TaskOutcomeWire,
    result: CompressionResultMessage? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil
  ) {
    queue.sync { _ = lastPercent.removeValue(forKey: taskId) }
    let message = TaskTerminalMessage(
      taskId: taskId,
      outcome: outcome,
      result: result,
      errorCode: errorCode,
      errorMessage: errorMessage
    )
    let api = self.api
    DispatchQueue.main.async {
      api.onTaskTerminal(message: message) { _ in }
    }
  }
}
