import Cocoa
import FlutterMacOS

/// Single Flutter entry point: registers the image channel and the video
/// channel.
public final class PixelCompressorPlugin: NSObject, FlutterPlugin {
    private let imageHandler = ImageCompressHandler()
    private var videoHandler: VideoCompressHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PixelCompressorPlugin()

        let imageChannel = FlutterMethodChannel(
            name: ImageCompressHandler.channelName, binaryMessenger: registrar.messenger)
        imageChannel.setMethodCallHandler { [imageHandler = instance.imageHandler] call, result in
            imageHandler.handle(call, result: result)
        }

        let videoChannel = FlutterMethodChannel(
            name: VideoCompressHandler.channelName, binaryMessenger: registrar.messenger)
        // Flutter calls method-call handlers on the platform (main) thread.
        let videoHandler = MainActor.assumeIsolated { VideoCompressHandler(channel: videoChannel) }
        instance.videoHandler = videoHandler
        videoChannel.setMethodCallHandler { call, result in
            MainActor.assumeIsolated {
                videoHandler.handle(call, result: result)
            }
        }

        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        let videoHandler = self.videoHandler
        self.videoHandler = nil
        MainActor.assumeIsolated { videoHandler?.dispose() }
    }
}
