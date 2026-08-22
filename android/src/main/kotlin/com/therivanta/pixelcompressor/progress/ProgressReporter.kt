package com.therivanta.pixelcompressor.progress

import android.os.Handler
import android.os.Looper
import com.therivanta.pixelcompressor.CompressionResultMessage
import com.therivanta.pixelcompressor.CompressionStageWire
import com.therivanta.pixelcompressor.PixelCompressorProgressCallbackApi
import com.therivanta.pixelcompressor.ProgressEventMessage
import com.therivanta.pixelcompressor.TaskOutcomeWire
import com.therivanta.pixelcompressor.TaskTerminalMessage
import java.util.concurrent.ConcurrentHashMap

/**
 * Wraps the generated [PixelCompressorProgressCallbackApi], hopping to the
 * main thread before every call (required since the Pigeon FlutterApi
 * caller talks to a [android.os.Handler.getMainLooper]-bound BinaryMessenger)
 * and throttling [onProgress] emissions to at least a 1-point percent delta
 * per task so a tight sample/attempt loop doesn't flood the platform
 * channel. [onTaskTerminal] is never throttled — exactly one is guaranteed
 * per task.
 */
class ProgressReporter(private val callbackApi: PixelCompressorProgressCallbackApi) {
  private val mainHandler = Handler(Looper.getMainLooper())
  private val lastPercent = ConcurrentHashMap<String, Double>()

  fun onProgress(
    taskId: String,
    stage: CompressionStageWire,
    percent: Double,
    currentItemIndex: Long? = null,
    totalItems: Long? = null,
    note: String? = null,
  ) {
    val clamped = percent.coerceIn(0.0, 100.0)
    val previous = lastPercent[taskId]
    if (previous != null &&
      kotlin.math.abs(clamped - previous) < 1.0 &&
      clamped != 0.0 &&
      clamped != 100.0
    ) {
      return
    }
    lastPercent[taskId] = clamped

    val event = ProgressEventMessage(
      taskId = taskId,
      stage = stage,
      percent = clamped,
      currentItemIndex = currentItemIndex,
      totalItems = totalItems,
      note = note,
    )
    mainHandler.post {
      callbackApi.onProgress(event) { /* fire-and-forget: Dart side never fails this */ }
    }
  }

  fun onCompleted(taskId: String, result: CompressionResultMessage? = null) {
    lastPercent.remove(taskId)
    val message = TaskTerminalMessage(
      taskId = taskId,
      outcome = TaskOutcomeWire.COMPLETED,
      result = result,
    )
    mainHandler.post {
      callbackApi.onTaskTerminal(message) { }
    }
  }

  fun onFailed(taskId: String, errorCode: String, errorMessage: String?) {
    lastPercent.remove(taskId)
    val message = TaskTerminalMessage(
      taskId = taskId,
      outcome = TaskOutcomeWire.FAILED,
      errorCode = errorCode,
      errorMessage = errorMessage,
    )
    mainHandler.post {
      callbackApi.onTaskTerminal(message) { }
    }
  }

  fun onCancelled(taskId: String, errorMessage: String? = "Task was cancelled") {
    lastPercent.remove(taskId)
    val message = TaskTerminalMessage(
      taskId = taskId,
      outcome = TaskOutcomeWire.CANCELLED,
      errorCode = "cancelled",
      errorMessage = errorMessage,
    )
    mainHandler.post {
      callbackApi.onTaskTerminal(message) { }
    }
  }
}
