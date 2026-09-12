import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// Registers pixel_compressor's platform channel HostApis and dispatches
/// each call to the corresponding engine class. This class stays dispatch
/// only — no compression logic lives here (see `ImageEngine`,
/// `VideoEngine`, `ThumbnailEngine`, `MediaInfoEngine`, `CapabilityProbe`,
/// `CacheManager`).
///
/// Every HostApi method hands off to `workQueue` (concurrent, so an image
/// compress, a video compress, and a thumbnail batch can all run at once)
/// immediately and returns without blocking the calling thread, per the
/// Pigeon dispatch contract (no `TaskQueue` is configured, so the
/// generated dispatch itself runs on the main thread). Cancellable/
/// progress-emitting work (image/video/thumbnail) is wrapped in a
/// `DispatchWorkItem` registered with `TaskRegistry` so `TaskHostApi.cancel`
/// can cooperatively cancel it, and reports exactly one `onTaskTerminal`
/// event matching its Pigeon `completion` outcome. Every `ProgressReporter`
/// call and every Pigeon `completion` is hopped back to the main thread
/// before touching generated Pigeon callers.
public class PixelCompressorPlugin: NSObject, FlutterPlugin, ImageHostApi, VideoHostApi,
  ThumbnailHostApi, MetadataHostApi, CapabilityHostApi, TaskHostApi
{
  private let taskRegistry = TaskRegistry()
  private let cacheManager = CacheManager()
  private let progressReporter: ProgressReporter
  private let imageEngine: ImageEngine
  private let videoEngine: VideoEngine
  private let thumbnailEngine: ThumbnailEngine
  private let mediaInfoEngine = MediaInfoEngine()

  private let workQueue = DispatchQueue(
    label: "com.therivanta.pixel_compressor.engine", qos: .userInitiated, attributes: .concurrent)

  init(binaryMessenger: FlutterBinaryMessenger) {
    let callbackApi = PixelCompressorProgressCallbackApi(binaryMessenger: binaryMessenger)
    let reporter = ProgressReporter(api: callbackApi)
    progressReporter = reporter
    imageEngine = ImageEngine(
      cacheManager: cacheManager, taskRegistry: taskRegistry, progressReporter: reporter)
    videoEngine = VideoEngine(
      cacheManager: cacheManager, taskRegistry: taskRegistry, progressReporter: reporter)
    thumbnailEngine = ThumbnailEngine(
      cacheManager: cacheManager, taskRegistry: taskRegistry, progressReporter: reporter)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif
    let instance = PixelCompressorPlugin(binaryMessenger: messenger)
    setUpAllApis(binaryMessenger: messenger, api: instance)
  }

  private static func setUpAllApis(binaryMessenger: FlutterBinaryMessenger, api: PixelCompressorPlugin) {
    ImageHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    VideoHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    ThumbnailHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    MetadataHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    CapabilityHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
    TaskHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: api)
  }

  // MARK: - ImageHostApi / VideoHostApi / ThumbnailHostApi (cancellable, progress-emitting)

  func compressImage(
    request: ImageCompressRequest,
    completion: @escaping (Result<CompressionResultMessage, Error>) -> Void
  ) {
    dispatchCancellableTask(
      taskId: request.taskId,
      completion: completion,
      terminalResult: { $0 },
      work: { [imageEngine] in try imageEngine.compress(request: request) }
    )
  }

  func compressVideo(
    request: VideoCompressRequest,
    completion: @escaping (Result<CompressionResultMessage, Error>) -> Void
  ) {
    dispatchCancellableTask(
      taskId: request.taskId,
      completion: completion,
      terminalResult: { $0 },
      work: { [videoEngine] in try videoEngine.compress(request: request) }
    )
  }

  func generateThumbnails(
    request: ThumbnailRequest,
    completion: @escaping (Result<[ThumbnailResultMessage], Error>) -> Void
  ) {
    dispatchCancellableTask(
      taskId: request.taskId,
      completion: completion,
      terminalResult: { _ in nil },
      work: { [thumbnailEngine] in try thumbnailEngine.generate(request: request) }
    )
  }

  // MARK: - MetadataHostApi / CapabilityHostApi (fire-and-forget, no taskId)

  func getMediaInfo(
    request: MediaInfoRequest,
    completion: @escaping (Result<MediaInfoMessage, Error>) -> Void
  ) {
    workQueue.async { [mediaInfoEngine] in
      do {
        let result = try mediaInfoEngine.read(request: request)
        DispatchQueue.main.async { completion(.success(result)) }
      } catch {
        let mapped = PixelCompressorError.map(error)
        DispatchQueue.main.async { completion(.failure(mapped)) }
      }
    }
  }

  func capabilities(completion: @escaping (Result<CapabilitiesReportMessage, Error>) -> Void) {
    workQueue.async {
      let report = CapabilityProbe.probe()
      DispatchQueue.main.async { completion(.success(report)) }
    }
  }

  // MARK: - TaskHostApi

  func cancel(taskId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.success(taskRegistry.cancel(taskId: taskId)))
  }

  func cancelAll(completion: @escaping (Result<Void, Error>) -> Void) {
    taskRegistry.cancelAll()
    completion(.success(()))
  }

  func activeTaskIds(completion: @escaping (Result<[String], Error>) -> Void) {
    completion(.success(taskRegistry.activeTaskIds()))
  }

  // MARK: - Dispatch helper

  /// Wraps `work` in a `DispatchWorkItem`, registers it with `TaskRegistry`
  /// under `taskId` before dispatch (so a cancel racing the dispatch is
  /// never lost), runs it on `workQueue`, then unregisters and reports
  /// exactly one terminal event before hopping to the main thread to
  /// invoke `completion`. `terminalResult` extracts the
  /// `CompressionResultMessage` to attach to the terminal event from `T`
  /// (thumbnails have no single result message, so they pass `nil`).
  private func dispatchCancellableTask<T>(
    taskId: String,
    completion: @escaping (Result<T, Error>) -> Void,
    terminalResult: @escaping (T) -> CompressionResultMessage?,
    work: @escaping () throws -> T
  ) {
    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      do {
        let result = try work()
        self.taskRegistry.unregister(taskId: taskId)
        self.progressReporter.reportTerminal(
          taskId: taskId, outcome: .completed, result: terminalResult(result))
        DispatchQueue.main.async { completion(.success(result)) }
      } catch {
        self.taskRegistry.unregister(taskId: taskId)
        let mapped = PixelCompressorError.map(error)
        let outcome: TaskOutcomeWire = mapped.code == "cancelled" ? .cancelled : .failed
        self.progressReporter.reportTerminal(
          taskId: taskId, outcome: outcome, errorCode: mapped.code, errorMessage: mapped.message)
        DispatchQueue.main.async { completion(.failure(mapped)) }
      }
    }
    taskRegistry.register(taskId: taskId, workItem: workItem)
    workQueue.async(execute: workItem)
  }
}
