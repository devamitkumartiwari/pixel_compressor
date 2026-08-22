# pixel_compressor

Native **image and video** compression for Flutter — resizing, format conversion, rotation and EXIF handling, target-size compression, thumbnail generation, media metadata, batch processing with progress and cancellation, capability detection, and cache management. Built entirely on platform codecs (Android `MediaCodec`/`MediaMuxer`, iOS/macOS `AVFoundation`/`VideoToolbox`/`ImageIO`) — no FFmpeg, no heavy third-party native dependencies.

All processing happens on-device. Nothing is ever uploaded anywhere.

> **Project status: early.** The public Dart API is stable, and native compression is implemented on Android, iOS, and macOS — real image/video compression, not a stub. Android has been verified end to end on real hardware (image and video compression, capability detection, and cache management all confirmed against real files). iOS and macOS build and run cleanly against the same engines but haven't yet had a full on-device interactive pass. Web has no implementation yet. Track progress in [CHANGELOG.md](CHANGELOG.md).

## Platform support

| | Android | iOS | macOS | Web |
|---|---|---|---|---|
| Image compression | ✅ | ✅ | ✅ | ❌ |
| Video compression | ✅ | ✅ | ✅ | ❌ |
| Thumbnails | ✅ | ✅ | ✅ | ❌ |
| Metadata | ✅ | ✅ | ✅ | ❌ |

Windows and Linux are not supported.

**SPM Support: YES**
**CocoaPods Required: NO** (a CocoaPods-compatible podspec is included for apps not yet on Swift Package Manager)

## Install

```yaml
dependencies:
  pixel_compressor: ^0.0.1
```

```dart
import 'package:pixel_compressor/pixel_compressor.dart';
```

Every feature is reached through one facade, grouped by concern:

```dart
PixelCompressor.image          // compress a single image / a batch of images
PixelCompressor.video          // compress a single video / a batch of videos
PixelCompressor.thumbnails     // capture frames from a video
PixelCompressor.metadata       // read dimensions/duration/codec info
PixelCompressor.capabilities   // check which codecs this device can encode with
PixelCompressor.cache          // inspect/clear pixel_compressor's own output cache
PixelCompressor.tasks          // cancel a running compression by task id
PixelCompressor.progressStream // every task's progress, tagged by task id
```

## Quick start

```dart
final result = await PixelCompressor.image.compress(
  MediaSource.file(file),
  options: const ImageCompressOptions(quality: 80, maxWidth: 1920),
);

print('${result.originalSizeBytes} -> ${result.outputSizeBytes} bytes '
    '(${result.savedPercent.toStringAsFixed(1)}% smaller)');
```

`MediaSource.file(File)` and `MediaSource.path(String)` are the two supported inputs today — in-memory byte compression is planned for a follow-up release.

## Image compression

```dart
final result = await PixelCompressor.image.compress(
  MediaSource.file(file),
  options: const ImageCompressOptions(
    quality: 80,             // 1-100
    maxWidth: 1920,          // longest edge scaled down, aspect ratio kept
    maxHeight: 1920,
    format: ImageFormat.webp,   // null keeps the source's own format
    exifPolicy: ExifPolicy.strip, // strip (default) or keep, GPS-safe by default
    rotationDegrees: 0,      // 0/90/180/270, applied before compression
    targetSizeBytes: null,   // see "Target-size compression" below
  ),
  onProgress: (event) => print('${event.stage} ${event.percent}%'),
);
```

`CompressionResult` gives you everything needed to show a before/after: `originalSizeBytes`, `outputSizeBytes`, `savedBytes`, `savedPercent`, `compressionRatio`, `duration`, `codec`, `format`, and `outputFile`/`outputPath`.

## Video compression

Two modes, chosen via `VideoCompressOptions.mode`:

```dart
// Smart — pick a QualityPreset and let the native side derive
// resolution/bitrate/codec.
final result = await PixelCompressor.video.compress(
  MediaSource.file(file),
  options: const VideoCompressOptions(
    mode: CompressionMode.smart,
    preset: QualityPreset.medium, // veryLow, low, medium, high, veryHigh
  ),
  onProgress: (event) => print('${event.stage} ${event.percent}%'),
);

// Manual — set codec/bitrate/fps yourself.
final result2 = await PixelCompressor.video.compress(
  MediaSource.file(file),
  options: const VideoCompressOptions(
    mode: CompressionMode.manual,
    codec: VideoCodec.auto,  // h264, hevc, or auto (HEVC if hardware-supported, else H.264)
    bitrateBps: 4_000_000,
    fps: 30,
    maxWidth: 1280,
    maxHeight: 1280,
    audioEnabled: true,
    audioBitrateBps: 128_000,
    trimStart: Duration(seconds: 5),
    trimEnd: Duration(seconds: 25),
  ),
);
```

## Target-size compression

Set `targetSizeBytes` on either options class instead of (or alongside) `quality`/`bitrateBps`, and the native side re-encodes at decreasing quality/bitrate until the output fits — or throws `TargetSizeException` if it can't get there even at the lowest setting:

```dart
options: ImageCompressOptions(targetSizeBytes: 200 * 1024), // <= 200 KB
```

## Batch processing

`compressBatch` runs a list of sources through the same options one at a time, and **keeps going past a per-item failure** instead of aborting the whole job:

```dart
final batch = await PixelCompressor.image.compressBatch(
  files.map(MediaSource.file).toList(),
  options: const ImageCompressOptions(quality: 70, maxWidth: 1920),
  onProgress: (itemIndex, totalItems, event) =>
      print('item ${itemIndex + 1}/$totalItems: ${event.stage} ${event.percent}%'),
);

print('${batch.succeeded.length} ok, ${batch.failed.length} failed, '
    '${batch.savedBytes} bytes saved overall');
```

`VideoCompressor` has the same `compressBatch`. Each `BatchItemResult` carries either a `CompressionResult` or a `PixelCompressorException` for that item.

## Thumbnails

```dart
final thumbnails = await PixelCompressor.thumbnails.generate(
  MediaSource.file(videoFile),
  ThumbnailOptions(
    positions: [Duration(seconds: 1), Duration(seconds: 5), Duration(seconds: 10)],
    maxWidth: 320,
    maxHeight: 320,
    format: ImageFormat.jpeg,
    quality: 80,
  ),
);
```

Positions are validated against the source's real duration on the Dart side first — an out-of-range position throws `InvalidMediaException` immediately rather than failing partway through native decoding.

## Metadata

Read dimensions, duration, codecs, and EXIF presence without compressing anything:

```dart
final info = await PixelCompressor.metadata.read(MediaSource.file(file));
print('${info.mediaType} ${info.width}x${info.height} ${info.sizeBytes} bytes');
if (info.mediaType == MediaType.video) {
  print('${info.duration} @ ${info.fps}fps, ${info.videoCodec}/${info.audioCodec}');
}
```

## Capabilities

Check what a device can actually encode before you rely on it — e.g. before defaulting to HEVC or WebP:

```dart
final caps = await PixelCompressor.capabilities.check();
if (caps.supportsHevc) {
  // use VideoCodec.hevc
}
```

`Capabilities` reports `h264Encode`/`hevcEncode`/`aacEncode`/`webpEncode`/`heicEncode` as `CodecSupportStatus.supported | unsupported | unknown`, plus `maxHardwareWidth`/`maxHardwareHeight`.

## Cache management

Results written without an explicit `outputPath` go to a cache-managed temp directory:

```dart
final bytesUsed = await PixelCompressor.cache.size();
await PixelCompressor.cache.clear();
```

## Progress and cancellation

Every `compress()` call accepts an `onProgress` callback scoped to that one task. For a single stream across every concurrent task instead, use `PixelCompressor.progressStream` and filter by `event.taskId`.

Cancel a running task using the `taskId` from any of its progress events:

```dart
await PixelCompressor.tasks.cancel(taskId);   // cancels one task
await PixelCompressor.tasks.cancelAll();      // cancels everything in flight
```

A cancelled task's `compress()` Future completes with `CompressionCancelledException`.

## Error handling

Every failure surfaces as a typed subclass of the sealed `PixelCompressorException`, never a raw platform exception — `nativeCode` and `nativeMessage` always carry the underlying native error through:

```dart
try {
  await PixelCompressor.image.compress(MediaSource.file(file), options: options);
} on UnsupportedCodecException catch (e) {
  // e.g. HEVC/WebP requested but not available on this device
} on TargetSizeException catch (e) {
  // targetSizeBytes couldn't be reached even at the lowest quality
} on PixelCompressorException catch (e) {
  print('${e.nativeCode}: ${e.nativeMessage}');
}
```

Other subtypes: `UnsupportedMediaException`, `InvalidMediaException`, `PermissionDeniedException`, `InsufficientStorageException`, `EncodingException`, `DecodingException`, `MetadataException`, `PlatformNotSupportedException`.

## Example app

The [example app](example) is a full demo of every feature above — pick a real photo or video, tune the options with the same widgets a production app would use (quality slider, format picker, target-size field, trim range, ...), and see the before/after size, ratio, and timing for each run. It has one page per feature: Image, Video, Batch, Thumbnails, Metadata, Capabilities, and Cache. On Android this is showing real compression results today; iOS/macOS run the same UI against the same native engines.

```sh
cd example
flutter run
```

## Documentation

See [CHANGELOG.md](CHANGELOG.md) for release notes.
