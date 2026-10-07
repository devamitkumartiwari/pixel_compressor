import Flutter
import UIKit

/// Handles the `pixel_compressor/image` channel. Method names, argument
/// indices and error codes match the Dart side.
final class ImageCompressHandler {
    static let channelName = "pixel_compressor/image"

    nonisolated(unsafe) private static var showLog = false

    static func log(_ message: @autoclosure () -> String) {
        if showLog {
            NSLog("%@", message())
        }
    }

    /// Carries the non-Sendable Flutter objects across the background hop;
    /// each request is only touched by one thread at a time.
    private final class Request: @unchecked Sendable {
        let call: FlutterMethodCall
        let result: FlutterResult
        init(call: FlutterMethodCall, result: @escaping FlutterResult) {
            self.call = call
            self.result = result
        }

        /// Engine replies must happen on the platform thread.
        func reply(_ value: Any?) {
            DispatchQueue.main.async { self.result(value) }
        }

        func fail(_ code: String, _ message: String) {
            reply(FlutterError(code: code, message: message, details: nil))
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showLog":
            Self.showLog = (call.arguments as? Bool) ?? false
            result(1)
            return
        default:
            break
        }

        // Decode / resize / encode is CPU- and I/O-heavy; keep it off the
        // platform thread.
        let request = Request(call: call, result: result)
        DispatchQueue.global(qos: .userInitiated).async {
            switch request.call.method {
            case "compressWithList":
                Self.compressList(request)
            case "compressWithFile":
                Self.compressFile(request)
            case "compressWithFileAndGetFile":
                Self.compressFileToFile(request)
            default:
                request.reply(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: compressWithList

    private static func compressList(_ request: Request) {
        guard let args = request.call.arguments as? [Any], args.count >= 9,
              let list = args[0] as? FlutterStandardTypedData else {
            return request.fail("unknown", "Invalid arguments")
        }
        let source = list.data
        guard let image = ImageEncoder.decode(source) else {
            return request.fail("decode_failed",
                                "Input is not a decodable image (mime=\(ImageEncoder.mimeType(of: source)))")
        }
        guard var data = ImageEncoder.compress(
            image,
            minWidth: int(args[1]), minHeight: int(args[2]), quality: int(args[3]),
            rotate: int(args[4]), format: int(args[6]),
            resize: ResizeSpec(args: args, start: 9)), !data.isEmpty else {
            return request.fail("encode_failed", "Encoder returned no data")
        }
        if bool(args[7]), let withMetadata = ImageEncoder.copyingMetadata(from: source, into: data) {
            data = withMetadata
        }
        request.reply(FlutterStandardTypedData(bytes: data))
    }

    // MARK: compressWithFile

    private static func compressFile(_ request: Request) {
        guard let args = request.call.arguments as? [Any], args.count >= 10,
              let path = args[0] as? String else {
            return request.fail("unknown", "Invalid arguments")
        }
        guard let (source, image) = readImage(path, request) else { return }
        guard var data = ImageEncoder.compress(
            image,
            minWidth: int(args[1]), minHeight: int(args[2]), quality: int(args[3]),
            rotate: int(args[4]), format: int(args[6]),
            resize: ResizeSpec(args: args, start: 10)), !data.isEmpty else {
            return request.fail("encode_failed", "Encoder returned no data")
        }
        if bool(args[7]), let withMetadata = ImageEncoder.copyingMetadata(from: source, into: data) {
            data = withMetadata
        }
        request.reply(FlutterStandardTypedData(bytes: data))
    }

    // MARK: compressWithFileAndGetFile

    private static func compressFileToFile(_ request: Request) {
        guard let args = request.call.arguments as? [Any], args.count >= 11,
              let path = args[0] as? String,
              let targetPath = args[4] as? String else {
            return request.fail("unknown", "Invalid arguments")
        }
        guard let (source, image) = readImage(path, request) else { return }
        guard var data = ImageEncoder.compress(
            image,
            minWidth: int(args[1]), minHeight: int(args[2]), quality: int(args[3]),
            rotate: int(args[5]), format: int(args[7]),
            resize: ResizeSpec(args: args, start: 11)), !data.isEmpty else {
            return request.fail("encode_failed", "Encoder returned no data")
        }
        if bool(args[8]), let withMetadata = ImageEncoder.copyingMetadata(from: source, into: data) {
            data = withMetadata
        }

        let targetURL = URL(fileURLWithPath: targetPath)
        do {
            // A no-op when the directory exists; a real failure surfaces from
            // the write below.
            try? FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
            request.reply(targetPath)
        } catch {
            request.fail("io_failed", "Failed to write compressed data to \(targetPath)")
        }
    }

    // MARK: Helpers

    /// Reads and decodes the file, replying with io_failed / decode_failed
    /// and returning nil on failure.
    private static func readImage(_ path: String, _ request: Request) -> (Data, UIImage)? {
        guard let source = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            log("Input file could not be read (path=\(path))")
            request.fail("io_failed", "Input file could not be read (path=\(path))")
            return nil
        }
        guard let image = ImageEncoder.decode(source) else {
            let message = "Input file is not a decodable image (mime=\(ImageEncoder.mimeType(of: source)), path=\(path))"
            log(message)
            request.fail("decode_failed", message)
            return nil
        }
        return (source, image)
    }

    private static func int(_ value: Any) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func bool(_ value: Any) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }
}
