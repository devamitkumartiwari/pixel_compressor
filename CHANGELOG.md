## 0.2.0

* Fixed Android video rotation: rotation was previously written only as an
  MP4 orientation-hint metadata flag (`MediaMuxer.setOrientationHint`),
  which many server-side players and transcoders ignore, producing
  rotated/upside-down output even though on-device playback (which honors
  the hint) looked correct. Rotation is now baked directly into the
  encoded pixels via a GPU render pass, matching the approach already used
  on iOS/macOS.
* Hardened `rotationDegrees` validation (image and video, Android and
  iOS): the public API's 0/90/180/270 contract was previously enforced
  only by a Dart `assert`, which is compiled out of release builds. An
  out-of-range value now throws `InvalidMediaException` on the native
  side instead of silently producing wrong (video) or clipped (image)
  output.

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
