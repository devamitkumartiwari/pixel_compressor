# pixel_compressor

[![pub package](https://img.shields.io/pub/v/pixel_compressor.svg)](https://pub.dev/packages/pixel_compressor)
[![license: MIT](https://img.shields.io/github/license/devamitkumartiwari/pixel_compressor)](LICENSE)

Native **image and video** compression for Flutter — resizing, format conversion, rotation and EXIF handling, target-size compression, thumbnail generation, media metadata, batch processing with progress and cancellation, capability detection, and cache management. Built entirely on platform codecs (Android `MediaCodec`/`MediaMuxer`, iOS/macOS `AVFoundation`/`VideoToolbox`/`ImageIO`) — no FFmpeg, no heavy third-party native dependencies.

All processing happens on-device. Nothing is ever uploaded anywhere.

> **Project status: early.** The public Dart API is stable, and native compression is implemented on Android, iOS, and macOS — real image/video compression, not a stub. Android has been verified end to end on real hardware (image and video compression, capability detection, and cache management all confirmed against real files). iOS and macOS build and run cleanly against the same engines but haven't yet had a full on-device interactive pass. Web supports image compression (JPEG/PNG/WebP, via canvas) and image merge; video, thumbnails, metadata, and capabilities are not available on Web. Track progress in [CHANGELOG.md](CHANGELOG.md).

## See it in action

Captured from the [example app](example) running on a real Android device.

<table>
<tr>
<th>Image compression</th>
<th>Video compression</th>
<th>Image merge</th>
</tr>
<tr>
<td><img src="https://raw.githubusercontent.com/devamitkumartiwari/pixel_compressor/main/art/image_compression.gif" width="260"/></td>
<td><img src="https://raw.githubusercontent.com/devamitkumartiwari/pixel_compressor/main/art/video_compression.gif" width="260"/></td>
<td><img src="https://raw.githubusercontent.com/devamitkumartiwari/pixel_compressor/main/art/merge.gif" width="260"/></td>
</tr>
<tr>
<td>958 KB → 441 KB (54% smaller) in ~1.2s</td>
<td>11.7 MB → 1.37 MB (88% smaller) via hardware HEVC</td>
<td>Stitches N images into one, pure Dart — no native call</td>
</tr>
</table>

## Platform support

| | Android | iOS | macOS | Web |
|---|---|---|---|---|
| Image compression | ✅ | ✅ | ✅ | ✅¹ |
| Video compression | ✅ | ✅ | ✅ | ❌ |
| Thumbnails | ✅ | ✅ | ✅ | ❌ |
| Metadata | ✅ | ✅ | ✅ | ❌ |
| Image merge | ✅ | ✅ | ✅ | ✅ |

¹ Web image compression is JPEG/PNG/WebP only (no HEIC — no browser can encode it), and only from `MediaSource.bytes`/`.asset` (no real filesystem path in a browser). It's implemented with `<canvas>`/`OffscreenCanvas`, no external JS libraries.

Image merge is pure Dart (`dart:ui` canvas drawing, no platform channel) and JPEG/PNG/WebP image compression on Web runs on the browser's own canvas APIs — everything else in the table above is native-only.

Windows and Linux are not supported.

**SPM Support: YES**
**CocoaPods Required: NO** (a CocoaPods-compatible podspec is included for apps not yet on Swift Package Manager)

## Install

```yaml
dependencies:
  pixel_compressor: ^0.2.0
```

```dart
import 'package:pixel_compressor/pixel_compressor.dart';
```

Every feature is reached through one facade, grouped by concern:

```dart
PixelCompressor.image          // compress a single image / a batch of images
PixelCompressor.video          // compress a single video / a batch of videos
PixelCompressor.merge          // combine multiple images into one (pure Dart)
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

Four ways to point at a source, all accepted anywhere a `MediaSource` is expected:

```dart
MediaSource.file(file)                    // a File already resolved by the caller
MediaSource.path(path)                    // a filesystem path
MediaSource.bytes(bytes)                  // in-memory bytes — no temp File to manage yourself
MediaSource.asset('assets/sample.jpg')    // a Flutter asset bundled with the app
```

On Web, only `.bytes`/`.asset` are usable — there's no real filesystem to point a path at.

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
    autoCorrectOrientation: true, // bake the source's EXIF orientation upright (default)
    targetSizeBytes: null,   // see "Target-size compression" below
    deleteSourceOnSuccess: false, // delete the source file once compression succeeds
    returnBytes: false,      // also read the output back into CompressionResult.outputBytes
  ),
  onProgress: (event) => print('${event.stage} ${event.percent}%'),
);
```

`CompressionResult` gives you everything needed to show a before/after: `originalSizeBytes`, `outputSizeBytes`, `savedBytes`, `savedPercent`, `compressionRatio`, `duration`, `codec`, `format`, and `outputFile`/`outputPath` (plus `outputBytes` when `returnBytes: true`).

JPEG and PNG compression run entirely in Dart (via `package:image`) on Android/iOS/macOS/Web — no platform channel round-trip. WebP and HEIC still go through the native encoder on Android/iOS/macOS (WebP also works on Web, via canvas).

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

## Image merge

Stitch 2+ images together vertically or horizontally. This is pure Dart — no third-party dependencies, no platform channel — built entirely on `dart:ui`'s `Canvas`/`PictureRecorder`, so it works on every platform Flutter runs on, including Web:

```dart
final merged = await PixelCompressor.merge.combine(
  [MediaSource.file(a), MediaSource.file(b), MediaSource.file(c)],
  options: const MergeOptions(
    direction: MergeDirection.horizontal, // or .vertical (default)
    spacing: 8,           // gap between images, in output pixels
    scaleToFit: true,     // scale each image so its cross-axis size matches the others
  ),
);

print('${merged.width}x${merged.height}, ${merged.outputSizeBytes} bytes');
```

Output is **always PNG** — `dart:ui` has no built-in JPEG/WebP/HEIC encoder, and adding one would mean a third-party dependency. For another format or a target file size, pipe the merged PNG through the existing native compressor instead:

```dart
final jpeg = await PixelCompressor.image.compress(
  MediaSource.file(merged.outputFile),
  options: const ImageCompressOptions(format: ImageFormat.jpeg, targetSizeBytes: 500 * 1024),
);
```

`MergeOptions.outputPath: null` (the default) writes to a plain OS temp file — unlike the rest of the package, this is **not** tracked by `PixelCompressor.cache`. Pass an explicit `outputPath` if you need the output cleaned up by your own app.

For a live, on-screen preview instead of (or before) a headless merge, decode sources with `PixelCompressor.merge.decode()` and render a `MergeView`, then screenshot it with a `MergeCaptureController`:

```dart
final images = [for (final f in files) await PixelCompressor.merge.decode(MediaSource.file(f))];
final controller = MergeCaptureController();

MergeView(images: images, controller: controller, direction: MergeDirection.vertical);

// Later, e.g. from a button:
final png = await controller.capturePng();
```

`MergeView` does not own or dispose the images passed to it — dispose them yourself once you're done.

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

JPEG/PNG sources are read directly in Dart from just the file header (dimensions, EXIF presence, orientation) — no native call. Any other format, or a parse ambiguity, falls back to the native reader automatically.

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

Implemented entirely in Dart via `path_provider` — no platform channel call.

## Progress and cancellation

Every `compress()` call accepts an `onProgress` callback scoped to that one task. For a single stream across every concurrent task instead, use `PixelCompressor.progressStream` and filter by `event.taskId`.

Cancel a running task using the `taskId` from any of its progress events:

```dart
await PixelCompressor.tasks.cancel(taskId);   // cancels one task
await PixelCompressor.tasks.cancelAll();      // cancels everything in flight
```

A cancelled task's `compress()` Future completes with `CompressionCancelledException`. Cancellation is real for every task, including the pure-Dart JPEG/PNG image engine — it stops mid-encode rather than finishing anyway.

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

The [example app](example) is a full demo of every feature above — pick a real photo or video, tune the options with the same widgets a production app would use (quality slider, format picker, target-size field, trim range, ...), and see the before/after size, ratio, and timing for each run. It has one page per feature: Image, Video, Batch, Merge, Thumbnails, Metadata, Capabilities, and Cache. On Android this is showing real compression results today; iOS/macOS run the same UI against the same native engines.

```sh
cd example
flutter run
```

## Documentation

See [CHANGELOG.md](CHANGELOG.md) for release notes.
