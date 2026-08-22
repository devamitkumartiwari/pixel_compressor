package com.therivanta.pixelcompressor

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.therivanta.pixelcompressor.cache.CacheManager
import com.therivanta.pixelcompressor.capability.CapabilityProbe
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import com.therivanta.pixelcompressor.errors.toPixelCompressorError
import com.therivanta.pixelcompressor.image.ImageEngine
import com.therivanta.pixelcompressor.metadata.MediaInfoEngine
import com.therivanta.pixelcompressor.progress.ProgressReporter
import com.therivanta.pixelcompressor.tasks.TaskRegistry
import com.therivanta.pixelcompressor.thumbnail.ThumbnailEngine
import com.therivanta.pixelcompressor.video.VideoEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Registers pixel_compressor's platform channel HostApis and dispatches
 * each call to its engine class. This class stays dispatch only — no
 * compression logic lives here; it holds shared infra (task registry,
 * progress reporter, cache manager, capability probe) and every engine.
 *
 * Every HostApi method hands off to [pluginScope] (`Dispatchers.Default`)
 * immediately and returns without blocking the calling (platform) thread,
 * per the plugin's threading model. Every progress event and the final
 * Pigeon reply callback are hopped back to the main thread via
 * [mainHandler] before touching the generated Pigeon callers.
 */
class PixelCompressorPlugin :
  FlutterPlugin,
  ImageHostApi,
  VideoHostApi,
  ThumbnailHostApi,
  MetadataHostApi,
  CapabilityHostApi,
  CacheHostApi,
  TaskHostApi {

  private var pluginScope: CoroutineScope? = null
  private var taskRegistry: TaskRegistry? = null
  private var progressReporter: ProgressReporter? = null
  private var cacheManager: CacheManager? = null
  private var capabilityProbe: CapabilityProbe? = null
  private var imageEngine: ImageEngine? = null
  private var videoEngine: VideoEngine? = null
  private var thumbnailEngine: ThumbnailEngine? = null
  private var mediaInfoEngine: MediaInfoEngine? = null

  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val context: Context = binding.applicationContext
    val messenger = binding.binaryMessenger

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val registry = TaskRegistry()
    val reporter = ProgressReporter(PixelCompressorProgressCallbackApi(messenger, ""))
    val cache = CacheManager(context)
    val capability = CapabilityProbe()

    pluginScope = scope
    taskRegistry = registry
    progressReporter = reporter
    cacheManager = cache
    capabilityProbe = capability
    imageEngine = ImageEngine(context, cache, capability, reporter)
    videoEngine = VideoEngine(context, cache, capability, reporter)
    thumbnailEngine = ThumbnailEngine(context, cache, reporter)
    mediaInfoEngine = MediaInfoEngine()

    ImageHostApi.setUp(messenger, this)
    VideoHostApi.setUp(messenger, this)
    ThumbnailHostApi.setUp(messenger, this)
    MetadataHostApi.setUp(messenger, this)
    CapabilityHostApi.setUp(messenger, this)
    CacheHostApi.setUp(messenger, this)
    TaskHostApi.setUp(messenger, this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val messenger = binding.binaryMessenger
    ImageHostApi.setUp(messenger, null)
    VideoHostApi.setUp(messenger, null)
    ThumbnailHostApi.setUp(messenger, null)
    MetadataHostApi.setUp(messenger, null)
    CapabilityHostApi.setUp(messenger, null)
    CacheHostApi.setUp(messenger, null)
    TaskHostApi.setUp(messenger, null)

    taskRegistry?.cancelAll()
    pluginScope?.cancel()
    pluginScope = null
    taskRegistry = null
    progressReporter = null
    cacheManager = null
    capabilityProbe = null
    imageEngine = null
    videoEngine = null
    thumbnailEngine = null
    mediaInfoEngine = null
  }

  // ---------------------------------------------------------------------
  // ImageHostApi / VideoHostApi / ThumbnailHostApi — registered, tracked,
  // progress-reporting tasks.
  // ---------------------------------------------------------------------

  override fun compressImage(
    request: ImageCompressRequest,
    callback: (Result<CompressionResultMessage>) -> Unit,
  ) {
    runTask(request.taskId, callback, terminalResult = { it }) {
      imageEngine!!.compress(request)
    }
  }

  override fun compressVideo(
    request: VideoCompressRequest,
    callback: (Result<CompressionResultMessage>) -> Unit,
  ) {
    runTask(request.taskId, callback, terminalResult = { it }) {
      videoEngine!!.compress(request)
    }
  }

  override fun generateThumbnails(
    request: ThumbnailRequest,
    callback: (Result<List<ThumbnailResultMessage>>) -> Unit,
  ) {
    runTask(request.taskId, callback, terminalResult = { null }) {
      thumbnailEngine!!.generate(request)
    }
  }

  // ---------------------------------------------------------------------
  // MetadataHostApi / CapabilityHostApi / CacheHostApi / TaskHostApi —
  // quick, non-cancellable, non-progress-reporting calls. Still
  // dispatched off the calling thread and replied to on the main thread,
  // per the shared threading model.
  // ---------------------------------------------------------------------

  override fun getMediaInfo(
    request: MediaInfoRequest,
    callback: (Result<MediaInfoMessage>) -> Unit,
  ) {
    runSimple(callback) { mediaInfoEngine!!.getMediaInfo(request) }
  }

  override fun capabilities(callback: (Result<CapabilitiesReportMessage>) -> Unit) {
    runSimple(callback) { capabilityProbe!!.capabilities() }
  }

  override fun clearCache(callback: (Result<Unit>) -> Unit) {
    runSimple(callback) { cacheManager!!.clear() }
  }

  override fun getCacheSize(callback: (Result<Long>) -> Unit) {
    runSimple(callback) { cacheManager!!.size() }
  }

  override fun cancel(taskId: String, callback: (Result<Boolean>) -> Unit) {
    runSimple(callback) { taskRegistry!!.cancel(taskId) }
  }

  override fun cancelAll(callback: (Result<Unit>) -> Unit) {
    runSimple(callback) { taskRegistry!!.cancelAll() }
  }

  override fun activeTaskIds(callback: (Result<List<String>>) -> Unit) {
    runSimple(callback) { taskRegistry!!.activeTaskIds() }
  }

  // ---------------------------------------------------------------------
  // Dispatch helpers
  // ---------------------------------------------------------------------

  /** Runs a registered, cancellable, progress-reporting task: registers
   * its [Job] in [TaskRegistry] under [taskId], emits exactly one
   * `onTaskTerminal` matching the outcome, and unregisters on completion.
   */
  private fun <T> runTask(
    taskId: String,
    callback: (Result<T>) -> Unit,
    terminalResult: (T) -> CompressionResultMessage?,
    block: suspend () -> T,
  ) {
    val scope = pluginScope
    val registry = taskRegistry
    val reporter = progressReporter
    if (scope == null || registry == null || reporter == null) {
      replyOnMain(callback, Result.failure(notAttachedError()))
      return
    }

    lateinit var job: Job
    job = scope.launch {
      try {
        val result = block()
        registry.unregister(taskId)
        reporter.onCompleted(taskId, terminalResult(result))
        replyOnMain(callback, Result.success(result))
      } catch (e: CancellationException) {
        registry.unregister(taskId)
        reporter.onCancelled(taskId)
        replyOnMain(callback, Result.failure(PixelCompressorErrors.cancelled()))
      } catch (e: Throwable) {
        registry.unregister(taskId)
        val mapped = e.toPixelCompressorError()
        reporter.onFailed(taskId, mapped.code, mapped.message)
        replyOnMain(callback, Result.failure(mapped))
      }
    }
    registry.register(taskId, job)
  }

  /** Runs a quick, non-cancellable call off the calling thread, replying
   * on the main thread. Used for metadata/capabilities/cache/task
   * queries that aren't tracked in [TaskRegistry] or reported through
   * [ProgressReporter].
   */
  private fun <T> runSimple(callback: (Result<T>) -> Unit, block: suspend () -> T) {
    val scope = pluginScope
    if (scope == null) {
      replyOnMain(callback, Result.failure(notAttachedError()))
      return
    }
    scope.launch {
      try {
        val result = block()
        replyOnMain(callback, Result.success(result))
      } catch (e: Throwable) {
        replyOnMain(callback, Result.failure(e.toPixelCompressorError()))
      }
    }
  }

  private fun <T> replyOnMain(callback: (Result<T>) -> Unit, result: Result<T>) {
    mainHandler.post { callback(result) }
  }

  private fun notAttachedError() =
    PixelCompressorErrors.platformNotSupported("PixelCompressorPlugin is not attached to a Flutter engine")
}
