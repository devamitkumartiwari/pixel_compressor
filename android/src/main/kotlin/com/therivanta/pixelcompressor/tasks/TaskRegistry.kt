package com.therivanta.pixelcompressor.tasks

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Job

/**
 * Tracks every in-flight task's [Job] by `taskId`, so [TaskHostApi] can
 * cancel one or all of them and report which are active. Engine classes
 * register their coroutine [Job] at the start of work and unregister it
 * (success, failure, or cancellation) in a `finally` block.
 */
class TaskRegistry {
  private val jobs = ConcurrentHashMap<String, Job>()

  fun register(taskId: String, job: Job) {
    jobs[taskId] = job
  }

  fun unregister(taskId: String) {
    jobs.remove(taskId)
  }

  /** Returns true if a task with [taskId] was found and cancelled. */
  fun cancel(taskId: String): Boolean {
    val job = jobs[taskId] ?: return false
    job.cancel()
    return true
  }

  fun cancelAll() {
    jobs.values.forEach { it.cancel() }
  }

  fun activeTaskIds(): List<String> = jobs.keys.toList()
}
