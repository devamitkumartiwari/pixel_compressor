import Flutter
import UIKit

/// Single Flutter entry point: registers the image channel and the video
/// channel.
///
/// Works with both the UIScene lifecycle (FlutterSceneDelegate +
/// FlutterImplicitEngineDelegate) and the app-delegate lifecycle. It never
/// touches windows or view controllers; it only listens for background and
/// foreground transitions so a running video compression gets background
/// time instead of being suspended mid-write.
public final class PixelCompressorPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
    private let imageHandler = ImageCompressHandler()
    private var videoHandler: VideoCompressHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PixelCompressorPlugin()

        let imageChannel = FlutterMethodChannel(
            name: ImageCompressHandler.channelName, binaryMessenger: registrar.messenger())
        imageChannel.setMethodCallHandler { [imageHandler = instance.imageHandler] call, result in
            imageHandler.handle(call, result: result)
        }

        let videoChannel = FlutterMethodChannel(
            name: VideoCompressHandler.channelName, binaryMessenger: registrar.messenger())
        // Flutter calls method-call handlers on the platform (main) thread.
        let videoHandler = MainActor.assumeIsolated { VideoCompressHandler(channel: videoChannel) }
        instance.videoHandler = videoHandler
        videoChannel.setMethodCallHandler { call, result in
            MainActor.assumeIsolated {
                videoHandler.handle(call, result: result)
            }
        }

        // UIKit sends either the scene or the application callbacks,
        // depending on which lifecycle the host app uses.
        registrar.addSceneDelegate(instance)
        registrar.addApplicationDelegate(instance)
        registrar.publish(instance)
    }

    // MARK: - UIScene lifecycle

    public func sceneDidEnterBackground(_ scene: UIScene) {
        didEnterBackground()
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        willEnterForeground()
    }

    // MARK: - App-delegate lifecycle (apps not yet on UIScene)

    public func applicationDidEnterBackground(_ application: UIApplication) {
        didEnterBackground()
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        willEnterForeground()
    }

    private func didEnterBackground() {
        let videoHandler = self.videoHandler
        MainActor.assumeIsolated { videoHandler?.didEnterBackground() }
    }

    private func willEnterForeground() {
        let videoHandler = self.videoHandler
        MainActor.assumeIsolated { videoHandler?.willEnterForeground() }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        let videoHandler = self.videoHandler
        self.videoHandler = nil
        MainActor.assumeIsolated { videoHandler?.dispose() }
    }
}
