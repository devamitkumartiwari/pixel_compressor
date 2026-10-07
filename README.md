# pixel_compressor

[![pub package](https://img.shields.io/pub/v/pixel_compressor.svg)](https://pub.dev/packages/pixel_compressor)
[![license](https://img.shields.io/github/license/devamitkumartiwari/pixel_compressor)](LICENSE)

One Flutter plugin to compress images, compress videos and merge images, all on the device.

Android video runs on **Media3 Transformer**; iOS and macOS use **AVFoundation**. There is no FFmpeg, nothing is uploaded, and no runtime permission is needed.

## Features

- **Images:** JPEG, PNG, WebP or HEIC from a file, bytes or an asset; min, max or exact sizing; EXIF rotation and metadata; header-only image info; batch compression.
- **Merging:** vertical, horizontal or grid collages with spacing, rounded corners and background colour, plus a live `PixelMergeView` preview. Works on every platform, including web.
- **Video:** H.264 or HEVC MP4 with presets, size, bitrate, trim and audio control; never larger than the source by default; progress, cancellation, thumbnails and media info.

## Installation

```yaml
dependencies:
  pixel_compressor: ^0.3.0
```

```dart
import 'package:pixel_compressor/pixel_compressor.dart';
```

No platform setup is needed. The plugin declares no storage or media permissions and writes its own outputs to the app's cache or temp directory. To let users choose files, use a picker that goes through the system photo picker.

The package uses `cross_file` 0.3 and re-exports `XFile` from it, so it works alongside `image_picker`, `file_picker`, `file_selector`, `camera` and `share_plus`.

## Quick start

```dart
// Image: shrink a photo to roughly 1920×1080 at quality 80.
final Uint8List jpeg = await PixelImageCompressor.compressFileToBytes(
  photo.path,
  quality: 80,
);

// Video: compress to 720p-class H.264 and listen to progress.
final sub = PixelVideoCompressor.progress$.subscribe((p) => debugPrint('$p%'));
final PixelMediaInfo? info = await PixelVideoCompressor.compressVideoFile(
  video.path,
  quality: .DefaultQuality,
);
sub.unsubscribe();
debugPrint('Output: ${info?.path}, ${info?.filesize} bytes');

// Merge: stack two images vertically into one PNG.
final PixelMergeResult merged = await PixelImageMerger.merge([
  PixelMergeSource.file(a.path),
  PixelMergeSource.file(b.path),
]);
```

---

## Image compression

All image APIs are static methods on `PixelImageCompressor`. On Android, iOS and macOS the work runs natively, off the UI thread. On the web it uses the browser's `<canvas>`.

### The four compress methods

#### `compressBytes`: bytes → bytes

Use it when the image is already in memory (from the network, a camera plugin or `XFile.readAsBytes()`). It is the only method besides `compressAsset` that works on the web.

```dart
final Uint8List output = await PixelImageCompressor.compressBytes(
  input,
  quality: 85,
  format: .webp,
);
```

#### `compressFileToBytes`: file path → bytes

Reads the file natively, so the original never has to be copied into Dart memory. `numberOfRetries` (default 5) retries the decode with a larger sample size if the device runs out of memory on a huge image (Android).

```dart
final Uint8List output = await PixelImageCompressor.compressFileToBytes(
  file.path,
  minWidth: 1280,
  minHeight: 720,
  quality: 80,
);
```

#### `compressFileToFile`: file path → file path

Writes the result straight to `targetPath` and returns it as an `XFile` (use `.path`, or `File(out.path)` for a `dart:io` `File`). Two rules:

- **The target's extension must match `format`**: `.jpg`/`.jpeg` for JPEG, `.png`, `.webp` or `.heic`. A mismatch throws `ArgumentError` (and asserts in debug). See [Validation](#validation-and-logging) to switch the check off.
- **The target must not be the source.** The native side truncates the target before it reads the source, so the same path would destroy your original. This throws `ArgumentError`.

```dart
final XFile out = await PixelImageCompressor.compressFileToFile(
  file.path,
  '${(await getTemporaryDirectory()).path}/photo_small.webp',
  quality: 80,
  format: .webp,
);
```

#### `compressAsset`: Flutter asset → bytes

```dart
final Uint8List output =
    await PixelImageCompressor.compressAsset('assets/images/banner.png');
```

Every method returns a **non-null** result and throws [`PixelCompressError`](#errors) on failure.

### Parameters

All four methods (and the `*WithInfo` and batch variants) accept the same options:

| Parameter | Default | Description |
|---|---|---|
| `minWidth` | `1920` | Lower width bound for downscaling. See [Resizing](#resizing). |
| `minHeight` | `1080` | Lower height bound for downscaling. |
| `maxWidth` | `null` | Upper width bound. The output always fits inside it. |
| `maxHeight` | `null` | Upper height bound. |
| `exactSize` | `null` | `PixelExactSize(w, h, fit:, padColor:)`: output exactly `w × h`. Overrides the min and max bounds. |
| `quality` | `95` | 1–100. Used by JPEG, WebP and HEIC; PNG is lossless and ignores it. |
| `format` | `PixelImageFormat.jpeg` | Output format. |
| `rotate` | `0` | Extra clockwise rotation in degrees, applied after the EXIF correction. |
| `autoCorrectionAngle` | `true` | Read the EXIF orientation and rotate the pixels upright. |
| `keepExif` | `false` | Copy the source's EXIF metadata into the output. The orientation tag is reset, because the pixels are already rotated. |
| `inSampleSize` | `1` | Android decode subsampling (2 = decode at half size). Speeds up decoding huge images. Not available on `compressAsset`. |
| `numberOfRetries` | `5` | File methods only: decode retries on Android out-of-memory. |

### Resizing

There are three ways to control the output size. They're applied in this order:

1. **`minWidth` / `minHeight`: lower bounds (the default).** The image is scaled down, keeping its aspect ratio, until one side reaches its bound. It is **never scaled up**. With the defaults, a 4000×3000 photo becomes 1920×1440, because the width reaches 1920 first. A 1200×800 image is left alone.
2. **`maxWidth` / `maxHeight`: upper bounds.** Applied after step 1. The output always fits inside the box, aspect ratio kept. Use these when you need a hard limit such as "never wider than 1280".
3. **`exactSize`: an exact pixel size.** Applied last, after rotation. The min and max bounds are ignored. `fit` decides what happens when the aspect ratios differ:

| `PixelImageFit` | Result |
|---|---|
| `stretch` | Each axis scaled independently. Fills the box exactly, but distorts the image. |
| `contain` (default) | The whole image fits inside, and the rest is filled with `padColor` (ARGB, default opaque black). |
| `cover` | The box is filled completely and the overflow is cropped, centred. |

```dart
// A hard limit: never larger than 1280×1280, whatever the source size.
await PixelImageCompressor.compressFileToBytes(
  path,
  maxWidth: 1280,
  maxHeight: 1280,
);

// Square 224×224 model input, letterboxed with white.
await PixelImageCompressor.compressFileToBytes(
  path,
  exactSize: const PixelExactSize(
    224,
    224,
    fit: .contain,
    padColor: 0xFFFFFFFF,
  ),
);

// 400×400 avatar, centre-cropped.
await PixelImageCompressor.compressBytes(
  bytes,
  exactSize: const PixelExactSize(400, 400, fit: .cover),
  format: .webp,
);
```

> Tip: to compress without resizing, pass small min bounds (e.g. `minWidth: 1, minHeight: 1`) and no max bounds. The image is then never scaled down.

### Rotation, EXIF and colour

- **Orientation**: phone cameras often store pixels sideways with an EXIF orientation tag. With `autoCorrectionAngle: true` (the default) the pixels are rotated upright, so the output displays correctly everywhere, even in viewers that ignore EXIF.
- **`rotate`** adds a further clockwise rotation, for example from a "rotate" button in your UI.
- **`keepExif: true`** carries over the camera metadata (date, camera model, GPS and so on). Remove it (the default) when you upload user photos and don't want to leak location data. On Android it works for JPEG, PNG and WebP output. On iOS/macOS it uses ImageIO. The web ignores it.
- **Colour**: Android decodes into sRGB, so wide-gamut (Display P3) photos don't come out oversaturated. The result matches iOS.

### Output formats

`PixelImageFormat` has four values: `jpeg`, `png`, `webp` and `heic`.

- **JPEG**: the default. Universally supported, no transparency.
- **PNG**: lossless, keeps transparency. `quality` is ignored, so expect larger files for photos.
- **WebP**: usually 25–35% smaller than JPEG at the same quality, and supports transparency. Android uses the platform encoder (`WEBP_LOSSY` on API 30+), iOS uses SDWebImageWebPCoder and the web uses `<canvas>`. **There is no WebP encoder on macOS.**
- **HEIC**: about half the size of JPEG. iOS and macOS use ImageIO. Android uses `HeifWriter`, which needs a hardware HEIF encoder (most devices from 2018 on). Not available on the web.

### Output size and format: `*WithInfo` and `PixelImageInfo`

When you need the output's dimensions (to store alongside the upload, or to show "1920×1440, 312 KB"), use the `*WithInfo` variants. They take the same parameters and return a `PixelImageResult`:

```dart
final PixelImageResult r = await PixelImageCompressor.compressFileWithInfo(
  path,
  quality: 80,
);
debugPrint('${r.info.width}×${r.info.height} ${r.info.format}, ${r.bytes.length} B');

final PixelImageResult r2 = await PixelImageCompressor.compressBytesWithInfo(bytes);
```

`PixelImageInfo.fromBytes` reads the same information from **any** encoded image, by parsing only the header. It never decodes pixels, is pure Dart and works on every platform:

```dart
final PixelImageInfo? info = PixelImageInfo.fromBytes(bytes);
if (info != null) {
  debugPrint('${info.width}×${info.height}, ${info.format}, orientation ${info.orientation}');
}
```

| `PixelImageInfo` field | Meaning |
|---|---|
| `width`, `height` | Size **as displayed**, with the EXIF/HEIF rotation already applied. |
| `format` | `PixelImageFormat`, or `null` for formats this package doesn't write (GIF, BMP, AVIF…). Those are still measured. |
| `orientation` | EXIF orientation 1–8 (1 = upright). The HEIF `irot` box is mapped to 1/6/3/8. |

`fromBytes` returns `null` (it never throws) for unknown or truncated data.

### Batch compression

`compressFilesToBytes` compresses many files with a bounded number running at once. That's faster than doing them one by one, and doesn't exhaust memory the way starting them all at once can.

```dart
final List<PixelBatchItem> items = await PixelImageCompressor.compressFilesToBytes(
  paths,
  concurrency: 3,                       // default 2
  onProgress: (done, total) => setState(() => _progress = done / total),
  quality: 80,
  maxWidth: 2048,
  maxHeight: 2048,
);

for (final item in items) {
  if (item.error != null) {
    debugPrint('${item.path} failed: ${item.error!.code}');
  } else {
    debugPrint('${item.path}: ${item.info!.width}×${item.info!.height}, ${item.bytes!.length} B');
  }
}
```

- Results come back **in input order**, whatever order the files finished in.
- **A failing file doesn't stop the batch.** Its `PixelBatchItem.error` is set and `bytes`/`info` are `null`.
- `onProgress(done, total)` is called after each file.
- It accepts every option from the [parameters table](#parameters). `concurrency < 1` throws `ArgumentError`.

### Validation and logging

Before calling native code, the plugin checks that the target file name matches the format and that the format is supported on the current platform. You can adjust these checks:

```dart
// Allow a target extension that doesn't match the format (e.g. ".bin").
PixelImageCompressor.validator.ignoreCheckExtName = true;

// Skip the platform-support check for the format (e.g. HEIC/WebP).
PixelImageCompressor.ignoreCheckSupportPlatform(true);
// same as: PixelImageCompressor.validator.ignoreCheckSupportPlatform = true;

// Print native-side logs (Android logcat / Xcode console).
PixelImageCompressor.nativeLogEnabled = true;
```

`PixelImageFormatValidator` also exposes the checks it runs: `checkFileNameAndFormat(name, format)` and `checkSupportPlatform(format)`.

### Errors

Failures throw `PixelCompressError`, which has a human-readable `message` and a machine-readable `code`:

| `code` | Meaning |
|---|---|
| `unsupported_format` | The format can't be encoded on this platform or device (e.g. WebP on macOS, HEIC with no encoder). |
| `decode_failed` | The input isn't a decodable image, or it is corrupt. |
| `encode_failed` | Encoding the output failed. |
| `io_failed` | A file couldn't be read or written. |
| `invalid_input` | Bad arguments (used by merging, e.g. fewer than 2 sources or an empty source). |
| `unknown` | Anything else. Unrecognised native codes are passed through as they are. |

```dart
try {
  final bytes = await PixelImageCompressor.compressFileToBytes(path);
} on PixelCompressError catch (e) {
  switch (e.code) {
    case 'decode_failed':
      showSnackBar('That file isn\'t a valid image.');
    default:
      showSnackBar('Compression failed: ${e.message}');
  }
}
```

Programming mistakes throw `ArgumentError` instead: a mismatched extension, source equal to target, or `concurrency < 1`. Calling the plugin from a background isolate without `BackgroundIsolateBinaryMessenger.ensureInitialized`, or on an unsupported platform (Windows, Linux), throws `UnimplementedError` with a hint.

---

## Merging images

`PixelImageMerger.merge` combines two or more images into one, for collages, before/after comparisons, long screenshots or receipt stitching. It runs **in Dart** with Flutter's own image codecs, so it works on every platform, including the web.

It is built not to fail on large inputs. Image sizes are read from the headers first, the canvas is clamped to the output limits, and each image is decoded **directly at the size it's drawn at**. Ten 48 MP photos therefore don't take ten full-resolution decodes of memory. Formats that Flutter can't decode natively (such as HEIC on some platforms) are converted with the native compressor first.

### Basic merge

```dart
final PixelMergeResult result = await PixelImageMerger.merge(
  [
    PixelMergeSource.file(before.path),
    PixelMergeSource.file(after.path),
  ],
  options: const PixelMergeOptions(
    layout: .horizontal,
    spacing: 16,
    padding: 16,
    cornerRadius: 24,
    background: Color(0xFF101010),
    format: .jpeg,
    quality: 85,
  ),
);

Image.memory(result.bytes);
debugPrint('${result.width}×${result.height} in ${result.elapsed.inMilliseconds} ms');
```

### Sources: `PixelMergeSource`

| Constructor | Use for |
|---|---|
| `PixelMergeSource.file(path)` | A file on disk. Not available on the web. |
| `PixelMergeSource.bytes(bytes)` | Encoded image bytes (JPEG, PNG, WebP, HEIC, GIF, BMP). |
| `PixelMergeSource.asset(name)` | A Flutter asset, e.g. `'assets/frame.png'`. |

Sources can be mixed freely. The concrete classes are `PixelMergeFileSource`, `PixelMergeBytesSource` and `PixelMergeAssetSource` (a sealed hierarchy, so you can `switch` over them).

### Options: `PixelMergeOptions`

| Option | Default | Description |
|---|---|---|
| `layout` | `vertical` | `PixelMergeLayout.vertical` (one column), `horizontal` (one row) or `grid`. |
| `gridColumns` | `2` | Images per row for `grid`. |
| `spacing` | `0` | Gap between images, in output pixels. |
| `padding` | `0` | Margin around the whole collage, filled with `background`. |
| `cornerRadius` | `0` | Rounds each image's corners. |
| `alignment` | `center` | `PixelMergeAlignment.start`, `center` or `end`: cross-axis placement when images don't fill the cross axis. |
| `scaleToFit` | `true` | Scale images (aspect ratio kept) so they share the cross-axis size: the same width in a column, the same height in a row. `false` keeps native sizes. |
| `background` | white | Fills gaps and shows through transparent images. Forced opaque for JPEG and HEIC, which have no alpha channel. |
| `maxOutputWidth` / `maxOutputHeight` | `null` | The output is scaled down (never up) to fit. When both are `null`, the long side is limited to **4096 px**. |
| `format` | `png` | Output encoding. PNG comes straight from the renderer; other formats go through `PixelImageCompressor`. |
| `quality` | `90` | 1–100, for JPEG, WebP and HEIC. |
| `outputPath` | `null` | Also write the result to this file. Not available on the web. |

`spacing`, `padding` and `cornerRadius` are in output pixels **before** size clamping. If the collage is scaled down to fit the limits, they shrink proportionally, so the look stays the same.

Hard limits of **8192 px per side** and **32 megapixels** always apply, whatever you pass, so huge inputs can't exhaust memory.

`PixelMergeOptions.copyWith(...)` makes it easy to derive variants, such as the same layout exported as JPEG.

#### Layouts

- **`vertical`**: images stacked top to bottom. With `scaleToFit`, all of them get the same width. This is how you stitch long screenshots.
- **`horizontal`**: images side by side. With `scaleToFit`, all of them get the same height. Suits before/after comparisons.
- **`grid`**: rows of `gridColumns` images, filled left to right and then top to bottom. With `scaleToFit`, every full row is scaled to the same total width (a **justified gallery**, as on Flickr or Google Photos), so images of different aspect ratios line up without cropping. A short last row is placed using `alignment`.

### Result: `PixelMergeResult`

| Field | Description |
|---|---|
| `bytes` | The encoded image. |
| `width`, `height` | Final pixel size. |
| `format` | The `PixelImageFormat` used. |
| `path` | Set when `outputPath` was given. |
| `sourceCount` | Number of input images. |
| `elapsed` | Total render and encode time. |

### Live preview: `PixelMergeView` and `PixelMergeCaptureController`

`PixelMergeView` is a widget that shows the merge as you change the options. It uses the **same layout code and decoder** as `PixelImageMerger.merge`, renders at screen resolution (cheap), and re-renders when `sources` or `options` change. To export, attach a `PixelMergeCaptureController` and call `capture()`. That runs the full-resolution merge, so the file matches the preview exactly.

```dart
class CollageEditor extends StatefulWidget {
  const CollageEditor({super.key, required this.sources});
  final List<PixelMergeSource> sources;

  @override
  State<CollageEditor> createState() => _CollageEditorState();
}

class _CollageEditorState extends State<CollageEditor> {
  final _controller = PixelMergeCaptureController();
  var _layout = PixelMergeLayout.grid;

  PixelMergeOptions get _options => PixelMergeOptions(
        layout: _layout,
        gridColumns: 3,
        spacing: 8,
        cornerRadius: 12,
      );

  Future<void> _export() async {
    final result = await _controller.capture(
      // Optional: override options for the export only.
      options: _options.copyWith(format: .jpeg, quality: 85),
    );
    // result.bytes is the full-resolution image.
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PixelMergeView(
            sources: widget.sources,
            options: _options,
            controller: _controller,
            placeholder: const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error) => Center(child: Text(error.message)),
          ),
        ),
        FilledButton(onPressed: _export, child: const Text('Export')),
      ],
    );
  }
}
```

| `PixelMergeView` parameter | Description |
|---|---|
| `sources` | Images to merge (at least 2). |
| `options` | A `PixelMergeOptions`. The view caps the preview resolution itself. |
| `controller` | An optional `PixelMergeCaptureController` for exporting. |
| `placeholder` | Shown while rendering. Defaults to an empty box. |
| `errorBuilder` | `(context, PixelCompressError) → Widget`. Defaults to the error message. |

`PixelMergeCaptureController.isAttached` tells you whether a view is currently attached. `capture()` throws `PixelCompressError` (`invalid_input`) if none is.

### Merge errors

`merge` and `capture` throw `PixelCompressError` with these codes:

- `invalid_input`: fewer than 2 sources, an empty source, or a file source/`outputPath` on the web.
- `io_failed`: a file or asset couldn't be read, or the output couldn't be written.
- `decode_failed`: a source isn't a decodable image. The message names its index.
- `unsupported_format`: e.g. WebP output on macOS.
- `encode_failed`: rendering or encoding failed.

---

## Video compression

`PixelVideoCompressor` is a singleton that compresses videos to MP4, reports progress, makes thumbnails and reads media info. It runs on Android, iOS and macOS.

### Compressing and tracking progress

```dart
// Progress runs from 0 to 100. Subscribe before starting.
final PixelProgressSubscription sub =
    PixelVideoCompressor.progress$.subscribe((double progress) {
  setState(() => _progress = progress / 100);
});

try {
  final PixelMediaInfo? info = await PixelVideoCompressor.compressVideoFile(
    video.path,
    quality: .MediumQuality,
    deleteOrigin: false,
    includeAudio: true,
  );
  if (info == null) {
    // Native failure (details are printed to the debug console).
  } else if (info.isCancel == true) {
    // Cancelled by cancelVideoCompression().
  } else {
    debugPrint('Saved ${info.path}: ${info.filesize} bytes, ${info.width}×${info.height}');
  }
} finally {
  sub.unsubscribe();
}
```

`progress$` is a **broadcast** stream, so any number of widgets can listen at the same time. Instead of `subscribe`, you can use `progress$.stream` directly with a `StreamBuilder`:

```dart
StreamBuilder<double>(
  stream: PixelVideoCompressor.progress$.stream,
  builder: (context, snap) => LinearProgressIndicator(value: (snap.data ?? 0) / 100),
);
```

**Only one compression can run at a time.** Starting a second one while `PixelVideoCompressor.isCompressing` is `true` throws `StateError`.

### `compressVideoFile` parameters

| Parameter | Default | Description |
|---|---|---|
| `path` | required | Source video path. |
| `quality` | `DefaultQuality` | A size preset. See [Quality presets](#quality-presets). |
| `deleteOrigin` | `false` | Delete the source file after a successful compression. |
| `startTime` | `null` | Trim: start offset in **seconds**. |
| `duration` | `null` | Trim: length to keep in **seconds**, counted from `startTime`. |
| `includeAudio` | `true` | `false` removes the audio track. |
| `frameRate` | `30` | Maximum output frame rate. Sources at or below it are left unchanged. |
| `bitrate` | `null` | Target average video bitrate in bits per second, used as given. Without it, the bitrate is derived from the output size (see [Output size](#how-the-output-size-is-chosen)). |
| `maxWidth` / `maxHeight` | `null` | Fit the (display-oriented) output inside this box, aspect ratio kept, never upscaled. Combined with the preset: the smaller limit wins. |
| `codec` | `PixelVideoCodec.h264` | `h264` or `hevc`. See [Codec](#codec). |
| `keyFrameInterval` | `3` | Seconds between key frames. Lower values seek faster; higher values give smaller files. Must be > 0. |
| `audioBitrate` | `null` → 128 kbps (64 kbps mono) | AAC bitrate in bits per second. Must be > 0. |
| `audioSampleRate` | `null` → the source's, max 48 kHz | 8000–48000 Hz. |
| `audioChannels` | `null` → the source's, max 2 | `1` (mono) or `2` (stereo). |
| `preventLargerOutput` | `true` | Never produce a file larger than the source. See below. |
| `outputPath` | `null` → the plugin's cache dir | Where to write the MP4. Must end in `.mp4` and differ from `path`. Parent directories are created and an existing file is replaced. |

Invalid values throw `ArgumentError` before any native work starts.

```dart
// A 1080p HEVC upload copy: 4 Mbps, 15 s from 0:05, mono 64 kbps audio,
// written to a path you choose.
final info = await PixelVideoCompressor.compressVideoFile(
  video.path,
  quality: .Res1920x1080Quality,
  codec: .hevc,
  bitrate: 4000000,
  startTime: 5,
  duration: 15,
  audioChannels: 1,
  audioBitrate: 64000,
  outputPath: '${dir.path}/upload.mp4',
);
```

### Quality presets

`PixelVideoQuality` sets a maximum output size. The video is scaled down to fit it, keeping its aspect ratio and orientation, and is never scaled up.

| Preset | Max short side × long side |
|---|---|
| `LowQuality` | 360 px short side |
| `MediumQuality` | 640 px short side |
| `DefaultQuality` | 720 px short side |
| `HighestQuality` | Source size (no scaling, higher bitrate) |
| `Res640x480Quality` | 480 × 640 |
| `Res960x540Quality` | 540 × 960 |
| `Res1280x720Quality` | 720 × 1280 |
| `Res1920x1080Quality` | 1080 × 1920 |

The limits apply to the **displayed** size, so portrait and landscape videos are treated the same way. Android and iOS/macOS use the same table.

### Codec

| `PixelVideoCodec` | Notes |
|---|---|
| `h264` (default) | Plays everywhere: every browser, every device. |
| `hevc` | About 40% smaller at the same quality, but some browsers and older devices can't play it. Falls back to H.264 on Android devices without an HEVC encoder. |

### How the output size is chosen

Without an explicit `bitrate`, the video bitrate is estimated from the output resolution and frame rate. With `preventLargerOutput: true` (the default), it is also **capped below the source's bitrate**, so an already-small video doesn't grow. If the re-encoded file still comes out larger than the source, the original streams are kept (remuxed) instead. That fallback applies only when you didn't ask for a specific `bitrate`, size or trim, because then the output must be re-encoded.

Set `preventLargerOutput: false` to always re-encode with the estimated bitrate. When none of the audio options is set, Android keeps an existing AAC track as it is, without re-encoding.

**HDR** sources (HLG / HDR10, as recorded by recent iPhones and Pixels) are tone-mapped to SDR Rec.709, because the output is 8-bit. Without this, HDR videos look washed out after compression.

### Cancelling

```dart
await PixelVideoCompressor.cancelVideoCompression();
```

The pending `compressVideoFile` call then completes with the **source's** `PixelMediaInfo` and `isCancel == true`, on every platform. If nothing is running, nothing happens.

### Thumbnails

```dart
// JPEG bytes of the frame at 1.5 s, longest side at most 512 px.
final Uint8List? jpeg = await PixelVideoCompressor.thumbnailBytes(
  video.path,
  quality: 80,     // JPEG quality 1–100 (default 100)
  position: 1500,  // milliseconds; -1 (default) lets the platform choose, usually the first frame
  maxSize: 512,    // longest side in px (default 512)
);

// The same, written to a JPEG file in the plugin's cache.
final XFile thumb = await PixelVideoCompressor.thumbnailFile(video.path, position: 1500);
```

- `position` is in **milliseconds** on every platform, and the exact frame is returned.
- Thumbnails of rotated (portrait) videos come out upright.
- `thumbnailFile` writes one file per video and position (`<name>_<position>.jpg`), so you can extract several frames of the same video without overwriting earlier ones.

### Media info

```dart
final PixelMediaInfo info = await PixelVideoCompressor.readMediaInfo(video.path);
debugPrint(info.toJson().toString());
```

| `PixelMediaInfo` field | Description |
|---|---|
| `path` / `file` | Path of the video and an `XFile` for it (`File(info.path!)` if you need a `dart:io` `File`). |
| `title`, `author` | Container metadata, if present. |
| `width`, `height` | Display size, with rotation applied. |
| `orientation` | Rotation in degrees (Android). |
| `filesize` | Size in bytes. |
| `duration` | Duration in **milliseconds**. |
| `isCancel` | `true` when returned from a cancelled compression. |

`compressVideoFile` returns the same type for the output file.

### Cache, logging and lifecycle

```dart
// Delete everything the plugin wrote to its cache folder (compressed videos,
// thumbnails). Don't put your own files in that folder.
await PixelVideoCompressor.clearVideoCache();

// Native log verbosity (passed to the platform logger).
await PixelVideoCompressor.setNativeLogLevel(0);

// Drop the singleton (e.g. in tests). The next use creates a new one.
PixelVideoCompressor.dispose();
```

Outputs go to the app's cache (Android) or temp directory (iOS/macOS), so **no storage permission is needed**. These directories can be cleared by the OS. Move results you want to keep, or pass `outputPath`.

### Long videos on Android

The plugin doesn't start a service. If the app goes to the background during a long compression, Android may stop the work. To keep long exports running, wrap the call in your own foreground service of type `mediaProcessing` (Android 15+).

---

## Advanced: platform interface and types

These are exported mainly for testing:

- **`PixelImageCompressPlatform`**: the platform interface behind `PixelImageCompressor`. Assign `PixelImageCompressPlatform.instance` a fake in unit tests to avoid method channels. `UnsupportedPixelImageCompress` is the default on unsupported platforms and throws `UnimplementedError`.
- **`PixelImageFormatValidator`**: see [Validation and logging](#validation-and-logging).
- **`IPixelVideoCompressor`** / **`PixelVideoCompressMixin`**: the type of `PixelVideoCompressor` (a top-level getter that returns the singleton). The mixin provides `progress$`, `isCompressing` and the method `channel`. All the methods above come from the `PixelVideoCompress` extension.
- **`PixelObservable<T>`**: the type of `progress$`, with `subscribe`, `stream` and `notSubscribed`. **`PixelProgressSubscription`** holds the `unsubscribe` callback.
- **`PixelMediaMetadataKey`** / **`PixelMediaEnum`**: Android `MediaMetadataRetriever` key constants.

---

## Store compliance

**Google Play**
- The plugin declares no storage, media or other dangerous permissions. Pick files with the system photo picker.
- Media3 adds the normal install-time permissions `ACCESS_NETWORK_STATE` and `WAKE_LOCK`. Neither shows a prompt or needs a Play declaration. If your app doesn't otherwise need them, remove them in your app manifest with `tools:node="remove"`.
- The plugin and its dependencies ship no native `.so` libraries, so the 16 KB page-size requirement has nothing to check.

**App Store**
- A privacy manifest (`PrivacyInfo.xcprivacy`) is included: no tracking, no data collected, no required-reason APIs. SDWebImage ships its own manifest.
- Supports the UIScene lifecycle (`FlutterSceneDelegate` / `FlutterImplicitEngineDelegate`) and apps still on the app-delegate lifecycle, with no setup either way. The plugin registers only through the Flutter plugin registrar and never touches windows or view controllers. It listens for scene (or app) background events so that a video compression running when the user leaves the app gets background time to finish. If iOS ends that time first, `compressVideoFile` returns `null`.
- Builds without deprecation warnings on the iOS 27 SDK and passes Swift 6 concurrency checking.
- Outputs go to the temporary directory, which isn't backed up, as the iOS data storage guidelines require.

**macOS**
- Sandboxed apps need `com.apple.security.files.user-selected.read-only` (or `read-write`) to compress files the user picks.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `UnimplementedError … is not available` | Called from a background isolate (call `BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)` first), or the platform (Windows/Linux) isn't supported. On the web, file-based methods aren't available, so use `compressBytes`. |
| `ArgumentError` from `compressFileToFile` | The target extension doesn't match `format`, or the target is the source. |
| `unsupported_format` for WebP | You're on macOS, which has no WebP encoder. Use JPEG, PNG or HEIC. |
| `unsupported_format` for HEIC on Android | The device has no hardware HEIF encoder. Fall back to JPEG or WebP. |
| The image isn't smaller | PNG is lossless; try JPEG/WebP or a lower `quality`. Also check that the min/max bounds actually reduce the size. |
| The video isn't smaller | The source is already efficient. With `preventLargerOutput` the original streams are kept. Lower the `quality` preset, set `maxWidth`/`maxHeight` or `bitrate`, or use `hevc`. |
| `StateError` from `compressVideoFile` | A compression is already running. Check `isCompressing`, or cancel it first. |
| `compressVideoFile` returns `null` | A native error occurred. Its details are printed to the debug console. |

## Example app

[`example/`](example) exercises every API above in seven tabs: **Image**, **Batch**, **Inspect**, **Video**, **Thumbnails**, **Merge** (with the live `PixelMergeView` preview) and **Tools**. Three bundled sample images let you try it without picking anything. It picks your own images and videos with `wechat_assets_picker` (Android, iOS, macOS), which asks for photo-library access, and with the browser's file dialog on the web. The plugin itself still needs no permissions.

`example/integration_test/app_test.dart` drives every tab with the samples on a real device or simulator:

```sh
cd example
flutter test integration_test -d <device-id>
```

## Platform support

| Feature | Android | iOS | macOS | Web |
|---|:-:|:-:|:-:|:-:|
| `compressBytes` / `compressAsset` | ✅ | ✅ | ✅ | ✅ |
| `compressFileToBytes` / `compressFileToFile` | ✅ | ✅ | ✅ | ❌ |
| `compressBytesWithInfo` / `PixelImageInfo` | ✅ | ✅ | ✅ | ✅ |
| `compressFileWithInfo` / `compressFilesToBytes` | ✅ | ✅ | ✅ | ❌ |
| `PixelImageMerger` / `PixelMergeView` | ✅ | ✅ | ✅ | ✅¹ |
| Video compression | ✅ | ✅ | ✅ | ❌ |
| Video thumbnails / media info | ✅ | ✅ | ✅ | ❌ |

¹ On the web, merge sources must be bytes or assets, and `outputPath` isn't available.

**Output formats**

| `PixelImageFormat` | Android | iOS | macOS | Web |
|---|:-:|:-:|:-:|:-:|
| `jpeg` | ✅ | ✅ | ✅ | ✅ |
| `png` | ✅ | ✅ | ✅ | ✅ |
| `webp` | ✅ | ✅ (SDWebImageWebPCoder) | ❌ no encoder | ✅ (`<canvas>`) |
| `heic` | ✅ (needs a hardware HEIF encoder) | ✅ | ✅ | ❌ |

**Requirements**

| | |
|---|---|
| Android | minSdk 28, compileSdk/targetSdk 37 (Android 17) |
| iOS | 16.0+, built and tested against the iOS 27 SDK |
| macOS | 13.0+ |
| Dart / Flutter | Dart ≥ 3.13, Flutter ≥ 3.41 |
| Build systems | Swift Package Manager (CocoaPods podspec also included) |

## License

Apache 2.0, with third-party notices; see [LICENSE](LICENSE).
