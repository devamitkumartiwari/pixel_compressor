// Built on the async AVFoundation APIs (iOS 16 / macOS 13+) so nothing
// here uses API deprecated in the iOS 18+ / macOS 15+ SDKs.

import AVFoundation
#if os(iOS)
import Flutter
import UIKit
#else
import Cocoa
import FlutterMacOS
#endif

@MainActor
final class VideoCompressHandler {
    nonisolated static let channelName = "pixel_compressor/video"

    private let channelName = VideoCompressHandler.channelName
    private var exportTask: Task<Void, Never>?
    private var transcoder: VideoTranscoder?
    private let channel: FlutterMethodChannel
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "getByteThumbnail":
            guard let path = args["path"] as? String else { return badArgs(result) }
            let quality = (args["quality"] as? NSNumber)?.intValue ?? 100
            let position = (args["position"] as? NSNumber)?.int64Value ?? -1
            let maxSize = (args["maxSize"] as? NSNumber)?.intValue ?? 512
            Task { await getByteThumbnail(path, quality, position, maxSize, result) }
        case "getFileThumbnail":
            guard let path = args["path"] as? String else { return badArgs(result) }
            let quality = (args["quality"] as? NSNumber)?.intValue ?? 100
            let position = (args["position"] as? NSNumber)?.int64Value ?? -1
            let maxSize = (args["maxSize"] as? NSNumber)?.intValue ?? 512
            Task { await getFileThumbnail(path, quality, position, maxSize, result) }
        case "getMediaInfo":
            guard let path = args["path"] as? String else { return badArgs(result) }
            Task {
                let json = await getMediaInfoJson(path)
                result(VideoUtility.keyValueToJson(json))
            }
        case "compressVideo":
            guard let path = args["path"] as? String else { return badArgs(result) }
            let quality = (args["quality"] as? NSNumber)?.intValue ?? 0
            let deleteOrigin = args["deleteOrigin"] as? Bool ?? false
            let startTime = (args["startTime"] as? NSNumber)?.doubleValue
            let duration = (args["duration"] as? NSNumber)?.doubleValue
            let includeAudio = args["includeAudio"] as? Bool
            let frameRate = (args["frameRate"] as? NSNumber)?.intValue
            let options = CompressOptions(
                bitrate: (args["bitrate"] as? NSNumber)?.intValue,
                maxWidth: (args["maxWidth"] as? NSNumber)?.intValue,
                maxHeight: (args["maxHeight"] as? NSNumber)?.intValue,
                outputPath: args["outputPath"] as? String,
                hevc: args["codec"] as? String == "hevc",
                keyFrameInterval: (args["keyFrameInterval"] as? NSNumber)?.doubleValue ?? 3,
                audioBitrate: (args["audioBitrate"] as? NSNumber)?.intValue,
                audioSampleRate: (args["audioSampleRate"] as? NSNumber)?.intValue,
                audioChannels: (args["audioChannels"] as? NSNumber)?.intValue,
                preventLargerOutput: args["preventLargerOutput"] as? Bool ?? true)
            compressVideo(path, quality, deleteOrigin, startTime, duration, includeAudio,
                          frameRate, options, result)
        case "cancelCompression":
            cancelCompression(result)
        case "deleteAllCache":
            VideoUtility.deleteFile(VideoUtility.basePath(), clear: true)
            result(true)
        case "setLogLevel":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func badArgs(_ result: FlutterResult) {
        result(FlutterError(code: channelName, message: "Invalid arguments", details: nil))
    }

    // MARK: - Thumbnails

    /// [position] is in milliseconds, as documented on the Dart side; a
    /// negative value means the first frame.
    private func getBitMap(_ path: String, _ quality: Int, _ position: Int64, _ maxSize: Int) async -> Data? {
        let url = VideoUtility.getPathUrl(path)
        let asset = AvController.getVideoAsset(url)
        guard await AvController.getTrack(asset) != nil else { return nil }

        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        if maxSize > 0 {
            assetImgGenerate.maximumSize = CGSize(width: maxSize, height: maxSize)
        }
        // Exact frame at the requested time, like Android's OPTION_CLOSEST.
        assetImgGenerate.requestedTimeToleranceBefore = .zero
        assetImgGenerate.requestedTimeToleranceAfter = .zero

        let time = position < 0 ? CMTime.zero : CMTime(value: position, timescale: 1000)
        guard let (img, _) = try? await assetImgGenerate.image(at: time) else {
            return nil
        }
        let compressionQuality = CGFloat(0.01 * Double(quality))
        #if os(iOS)
        return UIImage(cgImage: img).jpegData(compressionQuality: compressionQuality)
        #else
        let bitmapRep = NSBitmapImageRep(cgImage: img)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #endif
    }

    private func getByteThumbnail(_ path: String, _ quality: Int, _ position: Int64, _ maxSize: Int,
                                  _ result: FlutterResult) async {
        guard let bitmap = await getBitMap(path, quality, position, maxSize) else {
            return result(FlutterError(code: channelName, message: "getByteThumbnail error",
                                       details: "Assume this is a corrupt video file"))
        }
        result(FlutterStandardTypedData(bytes: bitmap))
    }

    private func getFileThumbnail(_ path: String, _ quality: Int, _ position: Int64, _ maxSize: Int,
                                  _ result: FlutterResult) async {
        // One file per (video, position) so several frames don't overwrite
        // each other.
        let fileName = "\(VideoUtility.getFileName(path))_\(position)"
        let url = URL(fileURLWithPath: VideoUtility.basePath()).appendingPathComponent("\(fileName).jpg")
        // Delete the old thumbnail, never the source video.
        VideoUtility.deleteFile(url.path)
        guard let bitmap = await getBitMap(path, quality, position, maxSize),
              (try? bitmap.write(to: url)) != nil else {
            return result(FlutterError(code: channelName, message: "getFileThumbnail error",
                                       details: "getFileThumbnail error"))
        }
        // Plain file-system path: the percent-encoded absoluteString broke
        // names with spaces, '%' or non-ASCII characters on the Dart side.
        result(url.path)
    }

    // MARK: - Media info

    func getMediaInfoJson(_ path: String) async -> [String: Any?] {
        let url = VideoUtility.getPathUrl(path)
        let asset = AvController.getVideoAsset(url)
        guard let track = await AvController.getTrack(asset) else { return [:] }

        let orientation = await AvController.getVideoOrientation(track)

        let title = await AvController.getMetaDataByTag(asset, key: "title")
        let author = await AvController.getMetaDataByTag(asset, key: "author")

        let duration = ((try? await asset.load(.duration))?.seconds ?? 0) * 1000
        let filesize = (try? await track.load(.totalSampleDataLength)) ?? 0

        let (naturalSize, transform) = (try? await track.load(.naturalSize, .preferredTransform))
            ?? (.zero, .identity)
        let size = naturalSize.applying(transform)

        let width = abs(size.width)
        let height = abs(size.height)

        return [
            "path": VideoUtility.excludeFileProtocol(path),
            "title": title,
            "author": author,
            "width": width,
            "height": height,
            "duration": duration,
            "filesize": filesize,
            "orientation": orientation,
        ]
    }

    // MARK: - Compression

    /// Extra options after the base compressVideo arguments.
    private struct CompressOptions {
        let bitrate: Int?
        let maxWidth: Int?
        let maxHeight: Int?
        let outputPath: String?
        let hevc: Bool
        let keyFrameInterval: Double
        let audioBitrate: Int?
        let audioSampleRate: Int?
        let audioChannels: Int?
        let preventLargerOutput: Bool
    }

    private func compressVideo(_ path: String, _ quality: Int, _ deleteOrigin: Bool, _ startTime: Double?,
                               _ duration: Double?, _ includeAudio: Bool?, _ frameRate: Int?,
                               _ options: CompressOptions, _ result: @escaping FlutterResult) {
        exportTask = Task {
            let sourceVideoUrl = VideoUtility.getPathUrl(path)
            let sourceVideoAsset = AvController.getVideoAsset(sourceVideoUrl)
            guard let assetDuration = try? await sourceVideoAsset.load(.duration) else {
                return result(nil)
            }

            let compressionUrl: URL
            if let outputPath = options.outputPath {
                compressionUrl = URL(fileURLWithPath: outputPath)
                try? FileManager.default.createDirectory(
                    at: compressionUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                compressionUrl = URL(fileURLWithPath: VideoUtility.basePath())
                    .appendingPathComponent("\(VideoUtility.getFileName(path))\(UUID().uuidString).mp4")
            }

            // startTime / duration are seconds; clamp the range to the asset.
            let timescale = assetDuration.timescale
            let videoDuration = assetDuration.seconds
            let start = min(max(startTime ?? 0, 0), videoDuration)
            let length = min(duration.map { max($0, 0) } ?? videoDuration, videoDuration - start)
            let timeRange = CMTimeRange(
                start: CMTimeMakeWithSeconds(start, preferredTimescale: timescale),
                duration: CMTimeMakeWithSeconds(length, preferredTimescale: timescale))

            let transcoder = VideoTranscoder(VideoTranscodeRequest(
                sourceURL: sourceVideoUrl,
                outputURL: compressionUrl,
                timeRange: timeRange,
                includeAudio: includeAudio ?? true,
                frameRate: frameRate,
                quality: quality,
                bitrate: options.bitrate,
                maxWidth: options.maxWidth,
                maxHeight: options.maxHeight,
                allowPassthroughFallback: options.preventLargerOutput && startTime == nil && duration == nil
                    && options.bitrate == nil && options.maxWidth == nil && options.maxHeight == nil,
                hevc: options.hevc,
                keyFrameInterval: options.keyFrameInterval,
                audioBitrate: options.audioBitrate,
                audioSampleRate: options.audioSampleRate,
                audioChannels: options.audioChannels,
                capToSourceBitrate: options.preventLargerOutput))
            self.transcoder = transcoder

            let channel = self.channel
            let completed: Bool
            do {
                completed = try await transcoder.run { progress in
                    DispatchQueue.main.async {
                        channel.invokeMethod("updateProgress", arguments: "\(progress)")
                    }
                }
            } catch {
                NSLog("pixel_compressor: compressVideo failed: \(error)")
                self.transcoder = nil
                exportTask = nil
                endBackgroundTask()
                return result(nil)
            }
            self.transcoder = nil
            exportTask = nil
            endBackgroundTask()

            if !completed {
                // Cancelled: reply with the source info + isCancel.
                var json = await getMediaInfoJson(path)
                json["isCancel"] = true
                return result(VideoUtility.keyValueToJson(json))
            }
            if deleteOrigin {
                try? FileManager.default.removeItem(atPath: path)
            }
            var json = await getMediaInfoJson(compressionUrl.path)
            json["isCancel"] = false
            result(VideoUtility.keyValueToJson(json))
        }
    }

    private func cancelCompression(_ result: FlutterResult) {
        transcoder?.cancel()
        result("")
    }

    func dispose() {
        transcoder?.cancel()
        exportTask?.cancel()
        exportTask = nil
        endBackgroundTask()
    }

    #if os(iOS)
    /// Asks iOS for background time while a compression is running, so
    /// switching apps does not suspend the writer mid-file. When the time
    /// runs out the task is ended and the OS may suspend the app; the
    /// compression then fails through the normal error path.
    func didEnterBackground() {
        guard transcoder != nil, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "pixel_compressor.video") {
            [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
    }

    /// Back in the foreground: the background time is no longer needed.
    func willEnterForeground() {
        endBackgroundTask()
    }
    #endif

    private func endBackgroundTask() {
        #if os(iOS)
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        #endif
    }
}
