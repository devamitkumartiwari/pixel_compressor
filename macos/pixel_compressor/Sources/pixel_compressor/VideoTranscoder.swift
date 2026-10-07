// pixel_compressor: AVAssetReader → AVAssetWriter transcoder.
//
// Used instead of AVAssetExportSession presets, which pick
// their own bitrate and can make an already-small video several times larger.
// Here we choose the size and bitrate ourselves, with the same rules as the
// Android (Media3) implementation.

import AVFoundation
import CoreMedia

/// Output size and bitrate rules shared with Android
/// (`VideoCompressHandler.kt`).
enum VideoSizing {
    /// (max short side, max long side) per `PixelVideoQuality` index;
    /// nil = keep the source size (HighestQuality).
    static func limits(forQuality quality: Int) -> (short: CGFloat, long: CGFloat)? {
        switch quality {
        case 0: return (720, .greatestFiniteMagnitude)   // DefaultQuality
        case 1: return (360, .greatestFiniteMagnitude)   // LowQuality
        case 2: return (640, .greatestFiniteMagnitude)   // MediumQuality
        case 3: return nil                               // HighestQuality
        case 4: return (480, 640)
        case 5: return (540, 960)
        case 6: return (720, 1280)
        case 7: return (1080, 1920)
        default: return (340, .greatestFiniteMagnitude)
        }
    }

    /// Display-oriented output size: scaled down (never up) to the quality
    /// limits, then to the optional max box, rounded to even pixels.
    static func targetSize(display: CGSize, quality: Int, maxWidth: Int?, maxHeight: Int?) -> CGSize {
        let w = display.width
        let h = display.height
        guard w > 0, h > 0 else { return display }
        var scale: CGFloat = 1
        if let limits = limits(forQuality: quality) {
            scale = min(scale, limits.short / min(w, h), limits.long / max(w, h))
        }
        if let maxWidth = maxWidth, maxWidth > 0 {
            scale = min(scale, CGFloat(maxWidth) / w)
        }
        if let maxHeight = maxHeight, maxHeight > 0 {
            scale = min(scale, CGFloat(maxHeight) / h)
        }
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded(.down) * 2) }
        return CGSize(width: even(w * scale), height: even(h * scale))
    }

    /// Share of the source bitrate the output may use. Below 1 because the
    /// hardware H.264 encoders are less efficient than the encoders most
    /// sources come from, and overshoot their average on short clips.
    static let sourceBitrateFactor = 0.75

    /// The requested bitrate if given; otherwise a resolution-based estimate
    /// capped below the source's bitrate, so output can't grow.
    static func bitrate(size: CGSize, fps: Float, quality: Int, requested: Int?, sourceBitrate: Float) -> Int {
        if let requested = requested, requested > 0 {
            return requested
        }
        let divisor: Double = quality == 3 ? 5 : 10
        let estimate = Double(size.width) * Double(size.height) * Double(fps) / divisor
        let capped = sourceBitrate > 0 ? min(estimate, Double(sourceBitrate) * sourceBitrateFactor) : estimate
        return max(Int(capped), 100_000)
    }
}

struct VideoTranscodeRequest {
    let sourceURL: URL
    let outputURL: URL
    let timeRange: CMTimeRange?
    let includeAudio: Bool
    let frameRate: Int?
    let quality: Int
    let bitrate: Int?
    let maxWidth: Int?
    let maxHeight: Int?
    /// When re-encoding makes the file bigger, keep the original streams
    /// instead (remuxed to MP4). Only for preset-driven requests: an explicit
    /// bitrate, size or trim must be honoured exactly.
    let allowPassthroughFallback: Bool
    var hevc = false
    var keyFrameInterval = 3.0
    var audioBitrate: Int?
    var audioSampleRate: Int?
    var audioChannels: Int?
    /// Cap the derived bitrate below the source's (see VideoSizing).
    var capToSourceBitrate = true
}

enum VideoTranscodeError: Error {
    case noVideoTrack
    case setupFailed(String)
    case failed(Error?)
}

/// One transcode. `run` throws on failure and returns false when cancelled.
final class VideoTranscoder: @unchecked Sendable {
    private let request: VideoTranscodeRequest
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?

    init(_ request: VideoTranscodeRequest) {
        self.request = request
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        let reader = lock.withLock { () -> AVAssetReader? in
            cancelled = true
            return self.reader
        }
        reader?.cancelReading()
    }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws -> Bool {
        let asset = AVURLAsset(url: request.sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoTranscodeError.noVideoTrack
        }
        let audioTrack = request.includeAudio
            ? try await asset.loadTracks(withMediaType: .audio).first
            : nil
        let (naturalSize, transform, nominalFrameRate, sourceBitrate) =
            try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate)
        let assetDuration = try await asset.load(.duration)

        let displaySize = CGSize(width: abs(naturalSize.applying(transform).width),
                                 height: abs(naturalSize.applying(transform).height))
        let target = VideoSizing.targetSize(display: displaySize, quality: request.quality,
                                            maxWidth: request.maxWidth, maxHeight: request.maxHeight)
        let sourceFps = nominalFrameRate > 0 ? nominalFrameRate : 30
        let fps = min(Float(request.frameRate ?? 30), sourceFps)
        let bitrate = VideoSizing.bitrate(size: target, fps: fps, quality: request.quality,
                                          requested: request.bitrate,
                                          sourceBitrate: request.capToSourceBitrate ? sourceBitrate : 0)
        let range = request.timeRange ?? CMTimeRange(start: .zero, duration: assetDuration)

        // --- Reader ---------------------------------------------------------
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let cancelledEarly = lock.withLock { () -> Bool in
            self.reader = reader
            return cancelled
        }
        if cancelledEarly { return false }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        videoOutput.videoComposition = makeVideoComposition(
            track: videoTrack, naturalSize: naturalSize, transform: transform, displaySize: displaySize,
            target: target,
            fps: fps, duration: assetDuration)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoTranscodeError.setupFailed("video output") }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioSettings: [String: Any]?
        if let audioTrack = audioTrack {
            var (sampleRate, channels) = try await audioFormat(of: audioTrack)
            if let rate = request.audioSampleRate { sampleRate = Double(rate) }
            if let count = request.audioChannels { channels = count }
            let pcm: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcm)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
                audioSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: request.audioBitrate ?? (channels == 1 ? 64_000 : 128_000),
                ]
            }
        }

        // --- Writer ---------------------------------------------------------
        try? FileManager.default.removeItem(at: request.outputURL)
        let writer = try AVAssetWriter(outputURL: request.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalDurationKey: request.keyFrameInterval,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
        ]
        if !request.hevc {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: request.hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(target.width),
            AVVideoHeightKey: Int(target.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw VideoTranscodeError.setupFailed("video input") }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioSettings = audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else { throw VideoTranscodeError.failed(reader.error) }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw VideoTranscodeError.failed(writer.error)
        }
        writer.startSession(atSourceTime: range.start)

        // --- Pump -----------------------------------------------------------
        let reporter = ProgressReporter(range: range, report: progress)
        await withTaskGroup(of: Void.self) { group in
            let video = Pump(output: videoOutput, input: videoInput, owner: self,
                             queue: DispatchQueue(label: "pixel_compressor.video"), reporter: reporter)
            group.addTask { await video.run() }
            if let audioOutput = audioOutput, let audioInput = audioInput {
                let audio = Pump(output: audioOutput, input: audioInput, owner: self,
                                 queue: DispatchQueue(label: "pixel_compressor.audio"), reporter: nil)
                group.addTask { await audio.run() }
            }
        }

        if isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.outputURL)
            return false
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.outputURL)
            throw VideoTranscodeError.failed(reader.error)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw VideoTranscodeError.failed(writer.error)
        }
        if request.allowPassthroughFallback, try await outputIsLarger(than: request.sourceURL) {
            try await remux(asset: asset, videoTrack: videoTrack, audioTrack: audioTrack, transform: transform)
        }
        progress(100)
        return true
    }

    private func outputIsLarger(than source: URL) async throws -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let sourceSize = try source.resourceValues(forKeys: keys).fileSize ?? 0
        let outputSize = try request.outputURL.resourceValues(forKeys: keys).fileSize ?? 0
        return sourceSize > 0 && outputSize > sourceSize
    }

    /// Copies the compressed source streams into a fresh MP4 without
    /// re-encoding (keeps the rotation via the track transform).
    private func remux(asset: AVAsset, videoTrack: AVAssetTrack, audioTrack: AVAssetTrack?,
                       transform: CGAffineTransform) async throws {
        try? FileManager.default.removeItem(at: request.outputURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: request.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for track in [videoTrack, audioTrack].compactMap({ $0 }) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let hint = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            if track.mediaType == .video {
                input.transform = transform
            }
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw VideoTranscodeError.setupFailed("passthrough \(track.mediaType.rawValue)")
            }
            reader.add(output)
            writer.add(input)
            pairs.append((output, input))
        }

        guard reader.startReading() else { throw VideoTranscodeError.failed(reader.error) }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw VideoTranscodeError.failed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)
        await withTaskGroup(of: Void.self) { group in
            for (index, (output, input)) in pairs.enumerated() {
                let pump = Pump(output: output, input: input, owner: self,
                                queue: DispatchQueue(label: "pixel_compressor.remux.\(index)"), reporter: nil)
                group.addTask { await pump.run() }
            }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw VideoTranscodeError.failed(reader.error)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoTranscodeError.failed(writer.error) }
    }

    /// Rotation (preferredTransform), scaling to the target size, frame-rate
    /// cap and SDR Rec.709 output (tone-maps HLG/PQ sources).
    private func makeVideoComposition(track: AVAssetTrack, naturalSize: CGSize, transform: CGAffineTransform,
                                      displaySize: CGSize,
                                      target: CGSize, fps: Float, duration: CMTime) -> AVVideoComposition {
        // Normalise the track transform so the rotated frame starts at the
        // origin (not every muxer writes the translation that way), then
        // scale it to the target size.
        let rotatedBounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let placed = transform
            .concatenating(CGAffineTransform(translationX: -rotatedBounds.minX, y: -rotatedBounds.minY))
            .concatenating(CGAffineTransform(scaleX: target.width / max(displaySize.width, 1),
                                             y: target.height / max(displaySize.height, 1)))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(placed, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = target
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return composition
    }

    /// Source sample rate (capped to 48 kHz) and channel count (capped to
    /// stereo), so AAC encoding always gets a supported layout.
    private func audioFormat(of track: AVAssetTrack) async throws -> (Double, Int) {
        let descriptions = try await track.load(.formatDescriptions)
        var sampleRate = 44_100.0
        var channels = 2
        if let description = descriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            if asbd.mSampleRate > 0 { sampleRate = min(asbd.mSampleRate, 48_000) }
            if asbd.mChannelsPerFrame > 0 { channels = min(Int(asbd.mChannelsPerFrame), 2) }
        }
        return (sampleRate, channels)
    }
}

/// Throttled (100 ms) progress from video presentation timestamps.
private final class ProgressReporter: @unchecked Sendable {
    private let range: CMTimeRange
    private let report: @Sendable (Double) -> Void
    private var last = Date.distantPast

    init(range: CMTimeRange, report: @escaping @Sendable (Double) -> Void) {
        self.range = range
        self.report = report
    }

    func update(_ time: CMTime) {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return }
        last = now
        let total = range.duration.seconds
        guard total > 0 else { return }
        let done = (time - range.start).seconds
        report(min(max(done / total * 100, 0), 99.9))
    }
}

/// Copies samples from one reader output to one writer input on its own
/// queue. Only touched from that queue.
private final class Pump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private unowned let owner: VideoTranscoder
    private let queue: DispatchQueue
    private let reporter: ProgressReporter?
    private var finished = false

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, owner: VideoTranscoder,
         queue: DispatchQueue, reporter: ProgressReporter?) {
        self.output = output
        self.input = input
        self.owner = owner
        self.queue = queue
        self.reporter = reporter
    }

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    if owner.isCancelled {
                        finish(continuation)
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        finish(continuation)
                        return
                    }
                    reporter?.update(CMSampleBufferGetPresentationTimeStamp(sample))
                    if !input.append(sample) {
                        finish(continuation)
                        return
                    }
                }
            }
        }
    }

    private func finish(_ continuation: CheckedContinuation<Void, Never>) {
        guard !finished else { return }
        finished = true
        input.markAsFinished()
        continuation.resume()
    }
}
