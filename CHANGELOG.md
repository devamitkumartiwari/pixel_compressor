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
