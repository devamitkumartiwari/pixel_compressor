## 0.3.0

A rewrite of the image and video engines, with a new API and many fixes.

### Breaking changes

* **The whole public API has changed.** The `PixelCompressor` facade and its
  option/result models are gone. Where to find each feature now:

  | 0.2.0 | 0.3.0 |
  |---|---|
  | `PixelCompressor.image.compress` | `PixelImageCompressor.compressFileToBytes` / `compressFileToFile` / `compressBytes` / `compressAsset` |
  | `PixelCompressor.image.compressBatch` | `PixelImageCompressor.compressFilesToBytes` |
  | `PixelCompressor.video.compress` | `PixelVideoCompressor.compressVideoFile` |
  | `PixelCompressor.thumbnails.generate` | `PixelVideoCompressor.thumbnailBytes` / `thumbnailFile` |
  | `PixelCompressor.metadata.read` | `PixelVideoCompressor.readMediaInfo` (video), `PixelImageInfo.fromBytes` (image) |
  | `PixelCompressor.merge.combine` | `PixelImageMerger.merge` |
  | `MergeView` / `MergeCaptureController` | `PixelMergeView` / `PixelMergeCaptureController` |
  | `PixelCompressor.progressStream` | `PixelVideoCompressor.progress$` |
  | `ImageFormat` | `PixelImageFormat` |
  | `PixelCompressorException` and its subclasses | `PixelCompressError` |

* `compressFileToBytes`, `compressFileToFile` and `compressAsset` never return
  `null`. They throw `PixelCompressError` when something goes wrong.
* **Removed:** `MediaSource`, target-size compression, capability detection,
  the cache manager (`PixelCompressor.cache`), the task manager
  (`PixelCompressor.tasks`), `returnBytes`, `deleteSourceOnSuccess` and
  `autoCorrectOrientation` (use `autoCorrectionAngle`).
* Requires `cross_file` `>=0.3.5 <0.3.9`, Dart 3.13+ and Flutter 3.41+.
  `compressFileToFile` and `thumbnailFile` return an `XFile`, and
  `PixelMediaInfo.file` is an `XFile?` (`thumbnailFile` and `file` were
  `dart:io` `File`), so the package is WASM-compatible. Use `.path`, or
  `File(x.path)` where a `File` is needed.
* **Android:** the `WRITE_EXTERNAL_STORAGE` permission is gone. Output is
  written to the app cache.

### New features

**Images**

* `maxWidth` / `maxHeight` limit the output size while keeping the aspect
  ratio.
* `exactSize: PixelExactSize(w, h, fit:)` gives an exact output size, with
  `stretch`, `contain` (with a padding colour) or `cover`.
  Works on all platforms.
* `compressFileWithInfo` / `compressBytesWithInfo` also return the output's
  width, height and format.
* `compressFilesToBytes` compresses many files with limited concurrency. It
  reports progress, and an error on one file doesn't stop the others.
* `PixelImageInfo.fromBytes` reads the size of JPEG, PNG, WebP, HEIC, GIF and
  BMP images from the file header only. It respects EXIF/HEIF rotation and
  also works on the web.
* Android uses the `WEBP_LOSSY` / `WEBP_LOSSLESS` formats on API 30+.

**Video**

* New `compressVideoFile` options: `bitrate`, `maxWidth` /
  `maxHeight`, `outputPath`, `codec`
  (H.264 or HEVC), `keyFrameInterval`, `audioBitrate`, `audioSampleRate`,
  `audioChannels`, and `preventLargerOutput`.
* Thumbnails take a `maxSize` (512 px by default on every platform).
* `progress$` is a broadcast stream, so several listeners can
  subscribe at once.
* **iOS:** supports the UIScene lifecycle. The plugin registers as a scene
  delegate (and as an app delegate, for apps not yet migrated). A video
  compression that is running when the app goes to the background now keeps
  going for as long as iOS gives it background time.

**Web**

* WASM-compatible: the public library no longer imports `dart:io`.

**Merge**

* `PixelImageMerger.merge` combines images in vertical, horizontal or grid
  layouts. You can set spacing, padding, rounded corners, alignment,
  background colour and a maximum output size, and save as PNG, JPEG, WebP or
  HEIC.
* It takes file, bytes or asset sources and runs in pure Dart. Very large
  inputs are scaled down instead of failing: images are decoded at their
  final size, with limits of 8192 px per side and 32 MP. If something fails,
  the error says which source caused it.
* `PixelMergeView` + `PixelMergeCaptureController` show a live preview, and
  exporting from it uses the same renderer as `merge`.

### Fixes

**All platforms**

* An output format the platform can't encode (WebP on macOS, HEIC or WebP
  outside Android/iOS) now throws `PixelCompressError` with code
  `unsupported_format`, as documented, instead of `UnsupportedError`.
* Compressed video is never larger than the source: the bitrate is capped at
  the source's.
* Each quality preset now gives the same output size on Android, iOS and
  macOS.
* Trim range and thumbnail `position` mean the same thing on every platform.
* `thumbnailFile` writes one file per position and returns a plain path. This
  fixes file names containing `%`, spaces or CJK characters.

**Android**

* Media info had width and height swapped for 0° and 180° videos.
* Thumbnails of rotated videos are now upright.
* Thumbnail `position` is read as milliseconds and returns the exact frame.
  If a decoder can't seek exactly, it falls back to the nearest key frame
  instead of failing.
* Cancelling a video compression now returns `isCancel: true`, like iOS.
* On Android 12+, the encoder raised VBR bitrates to a quality floor, which
  made output bigger. CBR is now used when the encoder supports it.
* When compression wouldn't make the file smaller, the original streams are
  copied into the output without re-encoding.
* Short clips are much smaller: Media3's 400 KB `moov` reservation is
  replaced by a fast-start rewrite, which keeps the file streamable.
* Videos without audio no longer get a silent audio track added.
* Converting audio with 3 or more channels to mono/stereo no longer crashes.
* HDR videos are tone-mapped to SDR, so they no longer look washed out.
* Android 9 prefers non-Codec2 video encoders.
* A missing video frame no longer crashes.
* Photos are decoded into sRGB, so wide-gamut photos are no longer
  oversaturated.
* A failure while reading the output's media info could crash the app, and
  `MediaMetadataRetriever` wasn't released after errors.
* EXIF orientation is read without loading the whole file into memory.

**iOS / macOS**

* Thumbnails used to come back at full size. They now follow `maxSize` and
  are frame-exact.
* Video output is tagged SDR Rec.709, so HDR sources no longer look washed
  out.
* HEIC is encoded with ImageIO first.
* SDWebImage's global coder list grew on every call because the WebP coder
  was added again each time. It is now added once.
* Thumbnail cleanup deleted the wrong path (the source video's instead of the
  old thumbnail).

### Under the hood

* Native code is Kotlin and Swift only, with no `commons-io` dependency and
  a single Swift Package target. A CocoaPods podspec is still included.
* Android video uses Media3 Transformer 1.11.1.
* iOS/macOS video uses an AVAssetReader/AVAssetWriter pipeline instead of
  AVAssetExportSession presets. It shares the size table and bitrate rules
  with Android.
* iOS WebP support comes from SDWebImage and SDWebImageWebPCoder.
* Uses the async AVFoundation APIs. Builds with no deprecation warnings on the
  iOS 27 SDK and is clean under Swift 6 concurrency checking.
* Android Gradle: the Kotlin plugin is applied based on
  `android.builtInKotlin`, and the build no longer uses
  Gradle DSL that AGP 10 removes.
* The Dart code now uses current Dart 3.13 syntax (primary constructors, dot
  shorthands, null-aware elements). New lints in `analysis_options.yaml`
  keep it that way. The public API is unchanged.

## 0.2.0

* Fixed Android video rotation coming out wrong: since Android 5.0,
  `MediaCodec` auto-applies a source video's own rotation hint to the
  decoder's output `Surface` transform whenever it decodes to a `Surface`
  — a platform behavior this plugin didn't account for. The result was
  rotation being applied twice (once by the platform during decode, once
  by this plugin's own handling), most visibly wrong at 90°/270° source
  rotations. Fixed by zeroing the source format's rotation hint before
  configuring the decoder; the combined source + requested rotation is
  now carried forward as a standard `MediaMuxer.setOrientationHint()`
  container hint — the same mechanism camera apps themselves use.
* Hardened `rotationDegrees` validation (image and video, Android and
  iOS): the public API's 0/90/180/270 contract was previously enforced
  only by a Dart `assert`, which is compiled out of release builds. An
  out-of-range value now throws `InvalidMediaException` on the native
  side instead of silently producing wrong (video) or clipped (image)
  output.
* Added `MediaSource.bytes()` and `MediaSource.asset()` — compress
  in-memory bytes or a bundled Flutter asset directly, no temp `File`
  management required from the caller. Works alongside the existing
  `MediaSource.file()`/`.path()`.
* Added `ImageCompressOptions.returnBytes` / `VideoCompressOptions.returnBytes`
  — also read the compressed output back into `CompressionResult.outputBytes`
  without a separate disk read.
* Added `ImageCompressOptions.deleteSourceOnSuccess` /
  `VideoCompressOptions.deleteSourceOnSuccess` — delete the source file
  once compression succeeds.
* Added `ImageCompressOptions.autoCorrectOrientation` (default `true`) —
  bakes the source's EXIF orientation upright before compressing; set
  `false` to keep the source's raw, uncorrected pixel orientation.
* Added Web support for image compression (JPEG/PNG/WebP, via
  `<canvas>`/`OffscreenCanvas`, no external JS libraries) and for
  `PixelCompressor.merge` alongside it — `MediaSource.bytes`/`.asset` only,
  since a browser has no real filesystem path to compress from.
* JPEG and PNG compression now run entirely in Dart (via `package:image`)
  on Android/iOS/macOS/Web instead of round-tripping through a platform
  channel. WebP and HEIC are unchanged (native on Android/iOS/macOS; WebP
  also works on Web via canvas, HEIC cannot since no browser can encode
  it).
* `PixelCompressor.cache` is now implemented entirely in Dart (via
  `path_provider`) instead of a platform channel call — same cache
  directory roots as before (`getApplicationCacheDirectory()` resolves to
  the same OS cache root the native side already used), so existing
  cached files are still accounted for correctly.
* `PixelCompressor.tasks` is now backed entirely by Dart-side bookkeeping.
  `cancel()`/`activeTaskIds()` no longer need a platform channel round-trip
  for tasks Dart itself is running, and cancellation is now real (not a
  no-op) for the pure-Dart JPEG/PNG image engine — a cancelled compress
  now actually stops mid-encode instead of finishing anyway.
* `PixelCompressor.metadata` now reads JPEG/PNG dimensions and EXIF
  presence directly in Dart from just the file header, without a native
  call — falls back to the native reader automatically for any other
  format or on any parse ambiguity, so behavior is unchanged for
  WebP/HEIC/video sources.
* Video trim range (`trimStart`/`trimEnd`) is now validated on the Dart
  side before any platform call — an invalid range (`trimEnd` at or before
  `trimStart`) throws `InvalidMediaException` immediately instead of
  failing partway through native decoding.

## 0.1.0

* Added `PixelCompressor.merge` — combine multiple images into one, stitched
  vertically or horizontally. Pure Dart (`dart:ui` `Canvas`/`PictureRecorder`,
  no third-party dependencies, no platform channel), so it's the only feature
  that runs on every platform Flutter supports, including Web. Output is
  PNG; pipe through `PixelCompressor.image.compress` for other formats or a
  target file size. Includes `MergeView` + `MergeCaptureController` for a
  live on-screen preview with screenshot capture.

## 0.0.1

* Initial release: native image and video compression, resizing, format
  conversion, rotation and EXIF handling, target-size compression, thumbnail
  generation, media metadata, batch processing with progress and
  cancellation, capability detection, and cache management.
* Android and iOS full native implementation; macOS shares the same Apple
  engine sources. Web is not implemented yet.
* Android native compression verified end to end on real hardware (image and
  video compression, capability detection, cache management). iOS/macOS
  build and run cleanly against the same engines; on-device verification
  there is still pending.
